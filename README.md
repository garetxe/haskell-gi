# haskell-gi

Generate Haskell bindings for GObject Introspection capable libraries.

## Installation

To compile the bindings generated by `haskell-gi`, make sure that you have installed the necessary development packages for the libraries you are interested in. The following are examples for some common distributions. (If your distribution is not listed please send a pull request!)

### Fedora

```sh
sudo dnf install gobject-introspection-devel webkitgtk4-devel gtksourceview3-devel
```

### Debian / Ubuntu

```sh
sudo apt-get install libgirepository1.0-dev libwebkit2gtk-4.0-dev libgtksourceview-3.0-dev
```

### Arch Linux

```sh
sudo pacman -S gobject-introspection gobject-introspection-runtime gtksourceview3 webkit2gtk
```

### Mac OSX

Install [Homebrew](https://brew.sh/) and install GTK and GObject Introspection:

```sh
brew install gobject-introspection gtk4
```
Ensure the path to libffi (probably `/usr/local/opt/libffi/lib/pkgconfig`) is in the PKG_CONFIG_PATH environment variable.


### Windows

Please see [here](https://github.com/haskell-gi/haskell-gi/wiki/Using-haskell-gi-in-Windows) for detailed installation instructions in Windows.

## Using the generated bindings

The most recent versions of the generated bindings are available from hackage. To install, start by making sure that you have a recent (2.0 or later) version of `cabal-install`, for instance:
```sh
$ cabal install cabal-install
$ cabal --version
cabal-install version 2.4.1.0
compiled using version 2.4.1.0 of the Cabal library
```

Here is an example "Hello World" program:
```haskell
{-# LANGUAGE OverloadedStrings, OverloadedLabels, OverloadedRecordDot, ImplicitParams #-}
{- cabal:
build-depends: base >= 4.16, haskell-gi-base, gi-gtk4
-}
import Control.Monad (void)

import qualified GI.Gtk as Gtk
import Data.GI.Base

activate :: Gtk.Application -> IO ()
activate app = do
  button <- new Gtk.Button [#label := "Click me",
                            On #clicked (?self `set` [#sensitive := False,
                                                      #label := "Thanks for clicking me"])]

  window <- new Gtk.ApplicationWindow [#application := app,
                                       #title := "Hi there",
                                       #child := button]
  window.show

main :: IO ()
main = do
  app <- new Gtk.Application [#applicationId := "haskell-gi.example",
                              On #activate (activate ?self)]

  void $ app.run Nothing
```
This program uses the new `OverloadedRecordDot` extension in GHC 9.2, so make sure you have a recent enough version of GHC installed. To run this program, copy it to a file (`hello.hs`, say), and then
```sh
$ cabal run hello.hs
```
For a more involved example, see for instance [this WebKit example](https://github.com/haskell-gi/haskell-gi/tree/master/examples). Further documentation can be found in [the Wiki](https://github.com/haskell-gi/haskell-gi/wiki).

## Translating from the C API to the `haskell-gi` generated API

The translation from the original C API to haskell-gi is fairly
straightforward: for method names simply remove the library prefix
(`gtk`, `gdk`, etc.), and convert to camelCase. I.e. `gtk_widget_show`
becomes
[`widgetShow`](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Widget.html#v:widgetShow)
in the module `GI.Gtk` (provided by the `gi-gtk` package).

For properties, add the type of the object as a prefix: so the `sensitive` property of `GtkWidget` becomes [`widgetSensitive`](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Widget.html#v:widgetSensitive) in `gi-gtk`. These can be set using the `new` syntax, as follows:

    b <- new Button [widgetSensitive := True]

or using `set` after having created the button

    b `set` [widgetSensitive := False]

Alternatively you can use [`setWidgetSensitive`](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Widget.html#v:setWidgetSensitive) and friends to set properties individually if you don't like the list syntax.

Finally, for signals you want to use the `onTypeSignalName` functions, for example [`onButtonClicked`](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Button.html#v:onButtonClicked):

    onButtonClicked b $ do ...

This is the basic dictionary. Note that all the resulting symbols can be conveniently searched in [hoogle](http://hoogle.haskell.org).

There is also support for the `OverloadedLabels` extension in GHC 8.0 or higher. So the examples above can be shortened (by omitting the type that introduces the signal/property/method) to

    b <- new Button [#sensitive := True]
    on b #clicked $ do ...
    #show b

Hopefully this helps to get started! For any further questions there is a gitter channel that may be helpful at https://gitter.im/haskell-gi/haskell-gi.

##  Binding to new libraries

It should be rather easy to generate bindings to any library with `gobject-introspection` support, see the examples in the [bindings](https://github.com/haskell-gi/haskell-gi/tree/master/bindings) folder. Pull requests appreciated!

## Higher-Level Bindings

The bindings in `haskell-gi` aim for complete coverage of the bound APIs, but as a result they are imperative in flavour. For nicer, higher-level approaches based on these bindings, see:

* [gi-gtk-declarative](https://github.com/owickstrom/gi-gtk-declarative)
* [reactive-banana-gi-gtk](https://github.com/mr/reactive-banana-gi-gtk)

## Other Resources

* [Haskell at Work screencast: GTK+ Programming with Haskell](https://haskell-at-work.com/gtk-programming-with-haskell/)

---

[![Join the chat at https://gitter.im/haskell-gi/haskell-gi](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/haskell-gi/haskell-gi?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge) ![Linux CI](https://github.com/haskell-gi/haskell-gi/workflows/Linux%20CI/badge.svg)
