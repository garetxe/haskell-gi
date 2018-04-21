### 4.0.18

+ The return values of [`backForwardListGetNthItem`](https://hackage.haskell.org/package/gi-webkit2/docs/GI-WebKit2-Objects-BackForwardList.html#v:backForwardListGetNthItem), [`backForwardListGetBackItem`](https://hackage.haskell.org/package/gi-webkit2/docs/GI-WebKit2-Objects-BackForwardList.html#v:backForwardListGetBackItem), [`backForwardListGetForwardItem`](https://hackage.haskell.org/package/gi-webkit2/docs/GI-WebKit2-Objects-BackForwardList.html#v:backForwardListGetForwardItem) and [`backForwardListGetCurrentItem`](https://hackage.haskell.org/package/gi-webkit2/docs/GI-WebKit2-Objects-BackForwardList.html#v:backForwardListGetCurrentItem) can all be `NULL`, but were not marked as such. This fixes [issue 155](https://github.com/haskell-gi/haskell-gi/issues/155).

### 4.0.17

+ The `ignoreHosts` argument of [`networkProxySettingsNew`](https://hackage.haskell.org/package/gi-webkit2/docs/GI-WebKit2-Structs-NetworkProxySettings.html#v:networkProxySettingsNew) was being represented as `Maybe Text`, but it should have been `Maybe [Text]`. This fixes [issue 154](https://github.com/haskell-gi/haskell-gi/issues/154).

### 4.0.15

+ Remove enable-overloading flags, and use instead explicit CPP checks for 'haskell-gi-overloading-1.0', see [how to disable overloading](https://github.com/haskell-gi/haskell-gi/wiki/Overloading\#disabling-overloading).

