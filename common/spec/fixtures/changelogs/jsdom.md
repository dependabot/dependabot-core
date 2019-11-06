## 15.2.0

* Set `canvas` as an optional ``peerDependency`, which apparently helps with Yarn PnP support.

## 15.1.1

* Moved the `nonce` property from `HTMLScriptElement` and `HTMLStyleElement` to `HTMLElement`. Note that it is still just a simple reflection of the attribute, and has not been updated for the rest of the changes in [whatwg/html#2373](https://github.com/whatwg/html/pull/2373).

## 15.1.0

* Added the `Headers` class from the Fetch standard.
* Added the `element.translate` getter and setter.
* Fixed synchronous `XMLHttpRequest` on the newly-released Node.js v12.
* Fixed `form.elements` to exclude `<input type="image">` elements.
* Fixed event path iteration in shadow DOM cases, following spec fixes at [whatwg/dom#686](https://github.com/whatwg/dom/pull/686) and [whatwg/dom#750](https://github.com/whatwg/dom/pull/750).
* Fixed `pattern=""` form control validation to apply the given regular expression to the whole string. (kontomondo)

## 15.0.0

Several potentially-breaking changes, each of them fairly unlikely to actually break anything:

* `JSDOM.fromFile()` now treats `.xht` files as `application/xhtml+xml`, the same as it does for `.xhtml` and `.xml`. Previously, it would treat them as `text/html`.
* When using the `Blob` or `File` constructor with the `endings: "native"` option, jsdom will now convert line endings to `\n` on all operating systems, for consistency. Previously, on Windows, it would convert line endings to `\r\n`.
