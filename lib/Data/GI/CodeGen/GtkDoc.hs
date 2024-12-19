-- | A parser for gtk-doc formatted documentation, see
-- https://developer.gnome.org/gtk-doc-manual/ for the spec.
module Data.GI.CodeGen.GtkDoc
  ( parseGtkDoc
  , GtkDoc(..)
  , Token(..)
  , Language(..)
  , Link(..)
  , ListItem(..)
  , CRef(..)
  , DocSymbolName(..)
  , docName
  , resolveDocSymbol
  ) where

import Prelude hiding (takeWhile)

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative ((<$>), (<*))
#endif
#if !MIN_VERSION_base(4,13,0)
import Data.Monoid ((<>))
#endif
import Control.Applicative ((<|>))

import Data.GI.GIR.BasicTypes (Name(Name))

import Data.Attoparsec.Text
import Data.Char (isAlphaNum, isAlpha, isAscii)
import qualified Data.Text as T
import Data.Text (Text)

-- | A parsed gtk-doc token.
data Token = Literal Text
           | Comment Text
           | Verbatim Text
           | CodeBlock (Maybe Language) Text
           | ExternalLink Link
           | Image Link
           | List [ListItem]
           | SectionHeader Int GtkDoc -- ^ A section header of the given depth.
           | SymbolRef CRef
  deriving (Show, Eq)

-- | A link to a resource, either offline or a section of the documentation.
data Link = Link { linkName :: Text
                 , linkAddress :: Text }
  deriving (Show, Eq)

-- | An item in a list, given by a list of lines (not including ending
-- newlines). The list is always non-empty, so we represent it by the
-- first line and then a possibly empty list with the rest of the
-- lines.
data ListItem = ListItem GtkDoc [GtkDoc]
  deriving (Show, Eq)

-- | The language for an embedded code block.
newtype Language = Language Text
  deriving (Show, Eq)

-- | A reference to some symbol in the API.
data CRef = FunctionRef DocSymbolName
          | OldFunctionRef Text
          | MethodRef DocSymbolName Text
          | ParamRef Text
          | ConstantRef Text
          | SignalRef DocSymbolName Text
          | OldSignalRef Text Text
          | LocalSignalRef Text
          | PropertyRef DocSymbolName Text
          | OldPropertyRef Text Text
          | VMethodRef Text Text
          | VFuncRef DocSymbolName Text
          | StructFieldRef Text Text
          | EnumMemberRef DocSymbolName Text
          | CTypeRef Text
          | TypeRef DocSymbolName
          deriving (Show, Eq, Ord)

-- | Reference to a name (of a class, for instance) in the
-- documentation. It can be either relative to the module where the
-- documentation is, of in some other namespace.
data DocSymbolName = RelativeName Text
                     -- ^ The symbol without a namespace specified
                   | AbsoluteName Text Text
                     -- ^ Namespace and symbol
  deriving (Show, Eq, Ord)

-- | A parsed gtk-doc with fully resolved references.
newtype GtkDoc = GtkDoc [Token]
  deriving (Show, Eq)

-- | Parse the given gtk-doc formatted documentation.
--
-- === __Examples__
-- >>> parseGtkDoc ""
-- GtkDoc []
--
-- >>> parseGtkDoc "func()"
-- GtkDoc [SymbolRef (OldFunctionRef "func")]
--
-- >>> parseGtkDoc "literal"
-- GtkDoc [Literal "literal"]
--
-- >>> parseGtkDoc "This is a long literal"
-- GtkDoc [Literal "This is a long literal"]
--
-- >>> parseGtkDoc "Call foo() for free cookies"
-- GtkDoc [Literal "Call ",SymbolRef (OldFunctionRef "foo"),Literal " for free cookies"]
--
-- >>> parseGtkDoc "The signal ::activate is related to gtk_button_activate()."
-- GtkDoc [Literal "The signal ",SymbolRef (LocalSignalRef "activate"),Literal " is related to ",SymbolRef (OldFunctionRef "gtk_button_activate"),Literal "."]
--
-- >>> parseGtkDoc "The signal ##%#GtkButton::activate is related to gtk_button_activate()."
-- GtkDoc [Literal "The signal ##%",SymbolRef (OldSignalRef "GtkButton" "activate"),Literal " is related to ",SymbolRef (OldFunctionRef "gtk_button_activate"),Literal "."]
--
-- >>> parseGtkDoc "# A section\n\n## and a subsection ##\n"
-- GtkDoc [SectionHeader 1 (GtkDoc [Literal "A section"]),Literal "\n",SectionHeader 2 (GtkDoc [Literal "and a subsection "])]
--
-- >>> parseGtkDoc "Compact list:\n- First item\n- Second item"
-- GtkDoc [Literal "Compact list:\n",List [ListItem (GtkDoc [Literal "First item"]) [],ListItem (GtkDoc [Literal "Second item"]) []]]
--
-- >>> parseGtkDoc "Spaced list:\n\n- First item\n\n- Second item"
-- GtkDoc [Literal "Spaced list:\n",List [ListItem (GtkDoc [Literal "First item"]) [],ListItem (GtkDoc [Literal "Second item"]) []]]
--
-- >>> parseGtkDoc "List with urls:\n- [test](http://test)\n- ![](image.png)"
-- GtkDoc [Literal "List with urls:\n",List [ListItem (GtkDoc [ExternalLink (Link {linkName = "test", linkAddress = "http://test"})]) [],ListItem (GtkDoc [Image (Link {linkName = "", linkAddress = "image.png"})]) []]]
parseGtkDoc :: Text -> GtkDoc
parseGtkDoc raw =
  case parseOnly (parseTokens <* endOfInput) raw of
    Left e ->
      error $ "gtk-doc parsing failed with error \"" <> e
      <> "\" on the input \"" <> T.unpack raw <> "\""
    Right tks -> GtkDoc . coalesceLiterals
                 . restoreSHPreNewlines . restoreListPreNewline $ tks

-- | `parseSectionHeader` eats the newline before the section header,
-- but `parseInitialSectionHeader` does not, since it only matches at
-- the beginning of the text. This restores the newlines eaten by
-- `parseSectionHeader`, so a `SectionHeader` returned by the parser
-- can always be assumed /not/ to have an implicit starting newline.
restoreSHPreNewlines :: [Token] -> [Token]
restoreSHPreNewlines [] = []
restoreSHPreNewlines (i : rest) = i : restoreNewlines rest
  where restoreNewlines :: [Token] -> [Token]
        restoreNewlines [] = []
        restoreNewlines (s@(SectionHeader _ _) : rest) =
          Literal "\n" : s : restoreNewlines rest
        restoreNewlines (x : rest) = x : restoreNewlines rest

-- | `parseList` eats the newline before the list, restore it.
restoreListPreNewline :: [Token] -> [Token]
restoreListPreNewline [] = []
restoreListPreNewline (l@(List _) : rest) =
  Literal "\n" : l : restoreListPreNewline rest
restoreListPreNewline (x : rest) = x : restoreListPreNewline rest

-- | Accumulate consecutive literals into a single literal.
coalesceLiterals :: [Token] -> [Token]
coalesceLiterals tks = go Nothing tks
  where
    go :: Maybe Text -> [Token] -> [Token]
    go Nothing  [] = []
    go (Just l) [] = [Literal l]
    go Nothing (Literal l : rest) = go (Just l) rest
    go (Just l) (Literal l' : rest) = go (Just (l <> l')) rest
    go Nothing (tk : rest) = tk : go Nothing rest
    go (Just l) (tk : rest) = Literal l : tk : go Nothing rest

-- | Parser for tokens.
parseTokens :: Parser [Token]
parseTokens = headerAndTokens <|> justTokens
  where -- In case the input starts by a section header.
        headerAndTokens :: Parser [Token]
        headerAndTokens = do
          header <- parseInitialSectionHeader
          tokens <- justTokens
          return (header : tokens)

        justTokens :: Parser [Token]
        justTokens = many' parseToken

-- | Parse a single token.
--
-- === __Examples__
-- >>> parseOnly (parseToken <* endOfInput) "func()"
-- Right (SymbolRef (OldFunctionRef "func"))
parseToken :: Parser Token
parseToken = -- Note that the parsers overlap, so this is not as
             -- efficient as it could be (if we had combined parsers
             -- and then branched, so that there is no
             -- backtracking). But speed is not an issue here, so for
             -- clarity we keep the parsers distinct. The exception
             -- is parseFunctionRef, since it does not complicate the
             -- parser much, and it is the main source of
             -- backtracking.
                 parseFunctionRef
             <|> parseMethod
             <|> parseConstructor
             <|> parseSignal
             <|> parseId
             <|> parseLocalSignal
             <|> parseProperty
             <|> parseVMethod
             <|> parseStructField
             <|> parseClass
             <|> parseCType
             <|> parseConstant
             <|> parseEnumMember
             <|> parseParam
             <|> parseEscaped
             <|> parseCodeBlock
             <|> parseVerbatim
             <|> parseUrl
             <|> parseImage
             <|> parseSectionHeader
             <|> parseList
             <|> parseComment
             <|> parseBoringLiteral

-- | Whether the given character is valid in a C identifier.
isCIdent :: Char -> Bool
isCIdent '_' = True
isCIdent c   = isAscii c && isAlphaNum c

-- | Something that could be a valid C identifier (loosely speaking,
-- we do not need to be too strict here).
parseCIdent :: Parser Text
parseCIdent = takeWhile1 isCIdent

-- | Parse a function ref
parseFunctionRef :: Parser Token
parseFunctionRef = parseOldFunctionRef <|> parseNewFunctionRef

-- | Parse an unresolved reference to a C symbol in new gtk-doc notation.
parseId :: Parser Token
parseId = do
  _ <- string "[id@"
  ident <- parseCIdent
  _ <- char ']'
  return (SymbolRef (OldFunctionRef ident))

-- | Parse a function ref, given by a valid C identifier followed by
-- '()', for instance 'gtk_widget_show()'. If the identifier is not
-- followed by "()", return it as a literal instead.
--
-- === __Examples__
-- >>> parseOnly (parseFunctionRef <* endOfInput) "test_func()"
-- Right (SymbolRef (OldFunctionRef "test_func"))
--
-- >>> parseOnly (parseFunctionRef <* endOfInput) "not_a_func"
-- Right (Literal "not_a_func")
parseOldFunctionRef :: Parser Token
parseOldFunctionRef = do
  ident <- parseCIdent
  option (Literal ident) (string "()" >>
                          return (SymbolRef (OldFunctionRef ident)))

-- | Parse a function name in new style, of the form
-- > [func@Namespace.c_func_name]
--
-- === __Examples__
-- >>> parseOnly (parseFunctionRef <* endOfInput) "[func@Gtk.init]"
-- Right (SymbolRef (FunctionRef (AbsoluteName "Gtk" "init")))
parseNewFunctionRef :: Parser Token
parseNewFunctionRef = do
  _ <- string "[func@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- takeWhile1 isCIdent
  _ <- char ']'
  return $ SymbolRef $ FunctionRef (AbsoluteName ns n)

-- | Parse a method name, of the form
-- > [method@Namespace.Object.c_func_name]
--
-- === __Examples__
-- >>> parseOnly (parseMethod <* endOfInput) "[method@Gtk.Button.set_child]"
-- Right (SymbolRef (MethodRef (AbsoluteName "Gtk" "Button") "set_child"))
--
-- >>> parseOnly (parseMethod <* endOfInput) "[func@Gtk.Settings.get_for_display]"
-- Right (SymbolRef (MethodRef (AbsoluteName "Gtk" "Settings") "get_for_display"))
parseMethod :: Parser Token
parseMethod = do
  _ <- string "[method@" <|> string "[func@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- takeWhile1 isCIdent
  _ <- char '.'
  method <- takeWhile1 isCIdent
  _ <- char ']'
  return $ SymbolRef $ MethodRef (AbsoluteName ns n) method

-- | Parse a reference to a constructor, of the form
-- > [ctor@Namespace.Object.c_func_name]
--
-- === __Examples__
-- >>> parseOnly (parseConstructor <* endOfInput) "[ctor@Gtk.Builder.new_from_file]"
-- Right (SymbolRef (MethodRef (AbsoluteName "Gtk" "Builder") "new_from_file"))
parseConstructor :: Parser Token
parseConstructor = do
  _ <- string "[ctor@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- takeWhile1 isCIdent
  _ <- char '.'
  method <- takeWhile1 isCIdent
  _ <- char ']'
  return $ SymbolRef $ MethodRef (AbsoluteName ns n) method

-- | Parse a reference to a type, of the form
-- > [class@Namespace.Name]
-- an interface of the form
-- > [iface@Namespace.Name]
-- or an enumeration type, of the form
-- > [enum@Namespace.Name]
--
-- === __Examples__
-- >>> parseOnly (parseClass <* endOfInput) "[class@Gtk.Dialog]"
-- Right (SymbolRef (TypeRef (AbsoluteName "Gtk" "Dialog")))
--
-- >>> parseOnly (parseClass <* endOfInput) "[iface@Gtk.Editable]"
-- Right (SymbolRef (TypeRef (AbsoluteName "Gtk" "Editable")))
--
-- >>> parseOnly (parseClass <* endOfInput) "[enum@Gtk.SizeRequestMode]"
-- Right (SymbolRef (TypeRef (AbsoluteName "Gtk" "SizeRequestMode")))
--
-- >>> parseOnly (parseClass <* endOfInput) "[struct@GLib.Variant]"
-- Right (SymbolRef (TypeRef (AbsoluteName "GLib" "Variant")))
parseClass :: Parser Token
parseClass = do
  _ <- string "[class@" <|> string "[iface@" <|>
       string "[enum@" <|> string "[struct@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- takeWhile1 isCIdent
  _ <- char ']'
  return $ SymbolRef $ TypeRef (AbsoluteName ns n)

-- | Parse a reference to a member of the enum, of the form
-- > [enum@Gtk.FontRendering.AUTOMATIC]
--
-- === __Examples__
-- >>> parseOnly (parseEnumMember <* endOfInput) "[enum@Gtk.FontRendering.AUTOMATIC]"
-- Right (SymbolRef (EnumMemberRef (AbsoluteName "Gtk" "FontRendering") "automatic"))
parseEnumMember :: Parser Token
parseEnumMember = do
  _ <- string "[enum@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- takeWhile1 isCIdent
  _ <- char '.'
  member <- takeWhile1 isCIdent
  _ <- char ']'
  -- Sometimes the references are written in uppercase while the name
  -- of the member in the introspection data is written in lowercase,
  -- so normalise everything to lowercase. (See the similar annotation
  -- in CtoHaskellMap.hs.)
  return $ SymbolRef $ EnumMemberRef (AbsoluteName ns n) (T.toLower member)

parseSignal :: Parser Token
parseSignal = parseOldSignal <|> parseNewSignal

-- | Parse an old style signal name, of the form
-- > #Object::signal
--
-- === __Examples__
-- >>> parseOnly (parseOldSignal <* endOfInput) "#GtkButton::activate"
-- Right (SymbolRef (OldSignalRef "GtkButton" "activate"))
parseOldSignal :: Parser Token
parseOldSignal = do
  _ <- char '#'
  obj <- parseCIdent
  _ <- string "::"
  signal <- signalOrPropName
  return (SymbolRef (OldSignalRef obj signal))

-- | Parse a new style signal ref, of the form
-- > [signal@Namespace.Object::signal-name]
--
-- === __Examples__
-- >>> parseOnly (parseNewSignal <* endOfInput) "[signal@Gtk.AboutDialog::activate-link]"
-- Right (SymbolRef (SignalRef (AbsoluteName "Gtk" "AboutDialog") "activate-link"))
parseNewSignal :: Parser Token
parseNewSignal = do
  _ <- string "[signal@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- parseCIdent
  _ <- string "::"
  signal <- takeWhile1 (\c -> (isAscii c && isAlpha c) || c == '-')
  _ <- char ']'
  return (SymbolRef (SignalRef (AbsoluteName ns n) signal))

-- | Parse a reference to a signal defined in the current module, of the form
-- > ::signal
--
-- === __Examples__
-- >>> parseOnly (parseLocalSignal <* endOfInput) "::activate"
-- Right (SymbolRef (LocalSignalRef "activate"))
parseLocalSignal :: Parser Token
parseLocalSignal = do
  _ <- string "::"
  signal <- signalOrPropName
  return (SymbolRef (LocalSignalRef signal))

-- | Parse a property name in the old style, of the form
-- > #Object:property
--
-- === __Examples__
-- >>> parseOnly (parseOldProperty <* endOfInput) "#GtkButton:always-show-image"
-- Right (SymbolRef (OldPropertyRef "GtkButton" "always-show-image"))
parseOldProperty :: Parser Token
parseOldProperty = do
  _ <- char '#'
  obj <- parseCIdent
  _ <- char ':'
  property <- signalOrPropName
  return (SymbolRef (OldPropertyRef obj property))

-- | Parse a property name in the new style:
-- > [property@Namespace.Object:property-name]
--
-- === __Examples__
-- >>> parseOnly (parseNewProperty <* endOfInput) "[property@Gtk.ProgressBar:show-text]"
-- Right (SymbolRef (PropertyRef (AbsoluteName "Gtk" "ProgressBar") "show-text"))
-- >>> parseOnly (parseNewProperty <* endOfInput) "[property@Gtk.Editable:width-chars]"
-- Right (SymbolRef (PropertyRef (AbsoluteName "Gtk" "Editable") "width-chars"))
parseNewProperty :: Parser Token
parseNewProperty = do
  _ <- string "[property@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- parseCIdent
  _ <- char ':'
  property <- takeWhile1 (\c -> (isAscii c && isAlpha c) || c == '-')
  _ <- char ']'
  return (SymbolRef (PropertyRef (AbsoluteName ns n) property))

-- | Parse a property
parseProperty :: Parser Token
parseProperty = parseOldProperty <|> parseNewProperty

-- | Parse an xml comment, of the form
-- > <!-- comment -->
-- Note that this function keeps spaces.
--
-- === __Examples__
-- >>> parseOnly (parseComment <* endOfInput) "<!-- comment -->"
-- Right (Comment " comment ")
parseComment :: Parser Token
parseComment = do
  comment <- string "<!--" *> manyTill anyChar (string "-->")
  return (Comment $ T.pack comment)

-- | Parse an old style reference to a virtual method, of the form
-- > #Struct.method()
--
-- === __Examples__
-- >>> parseOnly (parseOldVMethod <* endOfInput) "#Foo.bar()"
-- Right (SymbolRef (VMethodRef "Foo" "bar"))
parseOldVMethod :: Parser Token
parseOldVMethod = do
  _ <- char '#'
  obj <- parseCIdent
  _ <- char '.'
  method <- parseCIdent
  _ <- string "()"
  return (SymbolRef (VMethodRef obj method))

-- | Parse a new style reference to a virtual function, of the form
-- > [vfunc@Namespace.Object.vfunc_name]
--
-- >>> parseOnly (parseVFunc <* endOfInput) "[vfunc@Gtk.Widget.get_request_mode]"
-- Right (SymbolRef (VFuncRef (AbsoluteName "Gtk" "Widget") "get_request_mode"))
parseVFunc :: Parser Token
parseVFunc = do
  _ <- string "[vfunc@"
  ns <- takeWhile1 (\c -> isAscii c && isAlpha c)
  _ <- char '.'
  n <- parseCIdent
  _ <- char '.'
  vfunc <- parseCIdent
  _ <- char ']'
  return (SymbolRef (VFuncRef (AbsoluteName ns n) vfunc))

-- | Parse a reference to a virtual method
parseVMethod :: Parser Token
parseVMethod = parseOldVMethod <|> parseVFunc

-- | Parse a reference to a struct field, of the form
-- > #Struct.field
--
-- === __Examples__
-- >>> parseOnly (parseStructField <* endOfInput) "#Foo.bar"
-- Right (SymbolRef (StructFieldRef "Foo" "bar"))
parseStructField :: Parser Token
parseStructField = do
  _ <- char '#'
  obj <- parseCIdent
  _ <- char '.'
  field <- parseCIdent
  return (SymbolRef (StructFieldRef obj field))

-- | Parse a reference to a C type, of the form
-- > #Type
--
-- === __Examples__
-- >>> parseOnly (parseCType <* endOfInput) "#Foo"
-- Right (SymbolRef (CTypeRef "Foo"))
parseCType :: Parser Token
parseCType = do
  _ <- char '#'
  obj <- parseCIdent
  return (SymbolRef (CTypeRef obj))

-- | Parse a constant, of the form
-- > %CONSTANT_NAME
--
-- === __Examples__
-- >>> parseOnly (parseConstant <* endOfInput) "%TEST_CONSTANT"
-- Right (SymbolRef (ConstantRef "TEST_CONSTANT"))
parseConstant :: Parser Token
parseConstant = do
  _ <- char '%'
  c <- parseCIdent
  return (SymbolRef (ConstantRef c))

-- | Parse a reference to a parameter, of the form
-- > @param_name
--
-- === __Examples__
-- >>> parseOnly (parseParam <* endOfInput) "@test_param"
-- Right (SymbolRef (ParamRef "test_param"))
parseParam :: Parser Token
parseParam = do
  _ <- char '@'
  param <- parseCIdent
  return (SymbolRef (ParamRef param))

-- | Name of a signal or property name. Similar to a C identifier, but
-- hyphens are allowed too.
signalOrPropName :: Parser Text
signalOrPropName = takeWhile1 isSignalOrPropIdent
  where isSignalOrPropIdent :: Char -> Bool
        isSignalOrPropIdent '-' = True
        isSignalOrPropIdent c = isCIdent c

-- | Parse a escaped special character, i.e. one preceded by '\'.
parseEscaped :: Parser Token
parseEscaped = do
  _ <- char '\\'
  c <- satisfy (`elem` ("#@%\\`" :: [Char]))
  return $ Literal (T.singleton c)

-- | Parse a literal, i.e. anything without a known special
-- meaning. Note that this parser always consumes the first character,
-- regardless of what it is.
parseBoringLiteral :: Parser Token
parseBoringLiteral = do
  c <- anyChar
  boring <- takeWhile (not . special)
  return $ Literal (T.cons c boring)

-- | List of special characters from the point of view of the parser
-- (in the sense that they may be the beginning of something with a
-- special interpretation).
special :: Char -> Bool
special '#' = True
special '@' = True
special '%' = True
special '\\' = True
special '`' = True
special '|' = True
special '[' = True
special '!' = True
special '\n' = True
special ':' = True
special c = isCIdent c

-- | Parse a verbatim string, of the form
-- > `verbatim text`
--
-- === __Examples__
-- >>> parseOnly (parseVerbatim <* endOfInput) "`Example quote!`"
-- Right (Verbatim "Example quote!")
parseVerbatim :: Parser Token
parseVerbatim = do
  _ <- char '`'
  v <- takeWhile1 (/= '`')
  _ <- char '`'
  return $ Verbatim v

-- | Parse a URL in Markdown syntax, of the form
-- > [name](url)
--
-- === __Examples__
-- >>> parseOnly (parseUrl <* endOfInput) "[haskell](http://haskell.org)"
-- Right (ExternalLink (Link {linkName = "haskell", linkAddress = "http://haskell.org"}))
parseUrl :: Parser Token
parseUrl = do
  _ <- char '['
  name <- takeWhile1 (/= ']')
  _ <- string "]("
  address <- takeWhile1 (/= ')')
  _ <- char ')'
  return $ ExternalLink $ Link {linkName = name, linkAddress = address}

-- | Parse an image reference, of the form
-- > ![label](url)
--
-- === __Examples__
-- >>> parseOnly (parseImage <* endOfInput) "![](diagram.png)"
-- Right (Image (Link {linkName = "", linkAddress = "diagram.png"}))
parseImage :: Parser Token
parseImage = do
  _ <- string "!["
  name <- takeWhile (/= ']')
  _ <- string "]("
  address <- takeWhile1 (/= ')')
  _ <- char ')'
  return $ Image $ Link {linkName = name, linkAddress = address}

-- | Parse a code block embedded in the documentation.
parseCodeBlock :: Parser Token
parseCodeBlock = parseOldStyleCodeBlock <|> parseNewStyleCodeBlock

-- | Parse a new style code block, of the form
-- > ```c
-- > some c code
-- > ```
--
-- === __Examples__
-- >>> parseOnly (parseNewStyleCodeBlock <* endOfInput) "```c\nThis is C code\n```"
-- Right (CodeBlock (Just (Language "c")) "This is C code")
parseNewStyleCodeBlock :: Parser Token
parseNewStyleCodeBlock = do
  _ <- string "```"
  lang <- T.strip <$> takeWhile (/= '\n')
  _ <- char '\n'
  let maybeLang = if T.null lang then Nothing
                  else Just lang
  code <- T.pack <$> manyTill anyChar (string "\n```")
  return $ CodeBlock (Language <$> maybeLang) code

-- | Parse an old style code block, of the form
-- > |[<!-- language="C" --> code ]|
--
-- === __Examples__
-- >>> parseOnly (parseOldStyleCodeBlock <* endOfInput) "|[this is code]|"
-- Right (CodeBlock Nothing "this is code")
--
-- >>> parseOnly (parseOldStyleCodeBlock <* endOfInput) "|[<!-- language=\"C\"-->this is C code]|"
-- Right (CodeBlock (Just (Language "C")) "this is C code")
parseOldStyleCodeBlock :: Parser Token
parseOldStyleCodeBlock = do
  _ <- string "|["
  lang <- (Just <$> parseLanguage) <|> return Nothing
  code <- T.pack <$> manyTill anyChar (string "]|")
  return $ CodeBlock lang code

-- | Parse the language of a code block, specified as a comment.
parseLanguage :: Parser Language
parseLanguage = do
  _ <- string "<!--"
  skipSpace
  _ <- string "language=\""
  lang <- takeWhile1 (/= '"')
  _ <- char '"'
  skipSpace
  _ <- string "-->"
  return $ Language lang

-- | Parse a section header, given by a number of hash symbols, and
-- then ordinary text. Note that this parser "eats" the newline before
-- and after the section header.
parseSectionHeader :: Parser Token
parseSectionHeader = char '\n' >> parseInitialSectionHeader

-- | Parse a section header at the beginning of the text. I.e. this is
-- the same as `parseSectionHeader`, but we do not expect a newline as
-- a first character.
--
-- === __Examples__
-- >>> parseOnly (parseInitialSectionHeader <* endOfInput) "### Hello! ###\n"
-- Right (SectionHeader 3 (GtkDoc [Literal "Hello! "]))
--
-- >>> parseOnly (parseInitialSectionHeader <* endOfInput) "# Hello!\n"
-- Right (SectionHeader 1 (GtkDoc [Literal "Hello!"]))
parseInitialSectionHeader :: Parser Token
parseInitialSectionHeader = do
  hashes <- takeWhile1 (== '#')
  _ <- many1 space
  heading <- takeWhile1 (notInClass "#\n")
  _ <- (string hashes >> char '\n') <|> (char '\n')
  return $ SectionHeader (T.length hashes) (parseGtkDoc heading)

-- | Parse a list header. Note that the newline before the start of
-- the list is "eaten" by this parser, but is restored later by
-- `parseGtkDoc`.
--
-- === __Examples__
-- >>> parseOnly (parseList <* endOfInput) "\n- First item\n- Second item"
-- Right (List [ListItem (GtkDoc [Literal "First item"]) [],ListItem (GtkDoc [Literal "Second item"]) []])
--
-- >>> parseOnly (parseList <* endOfInput) "\n\n- Two line\n  item\n\n- Second item,\n  also two lines"
-- Right (List [ListItem (GtkDoc [Literal "Two line"]) [GtkDoc [Literal "item"]],ListItem (GtkDoc [Literal "Second item,"]) [GtkDoc [Literal "also two lines"]]])
parseList :: Parser Token
parseList = do
  items <- many1 parseListItem
  return $ List items
  where parseListItem :: Parser ListItem
        parseListItem = do
          _ <- char '\n'
          _ <- string "\n- " <|> string "- "
          first <- takeWhile1 (/= '\n')
          rest <- many' parseLine
          return $ ListItem (parseGtkDoc first) (map parseGtkDoc rest)

        parseLine :: Parser Text
        parseLine = string "\n  " >> takeWhile1 (/= '\n')

-- | Turn an ordinary `Name` into a `DocSymbolName`
docName :: Name -> DocSymbolName
docName (Name ns n) = AbsoluteName ns n

-- | Return a `Name` from a potentially relative `DocSymbolName`,
-- using the provided default namespace if the name is relative.
resolveDocSymbol :: DocSymbolName -> Text -> Name
resolveDocSymbol (AbsoluteName ns n) _ = Name ns n
resolveDocSymbol (RelativeName n) defaultNS = Name defaultNS n
