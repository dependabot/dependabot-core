Native JavaScript helpers
-------------------------

This directory contains helper functions for npm and yarn, natively written in
Javascript so that we can utilize the package managers internal APIs and other
native tooling for these ecosystems.

These helpers are called from the Ruby code via `run.js`, they are passed
arguments via stdin and return JSON data to stdout.

## Debugging

When working on these helpers, it's convenient to write some high level tests in
JavaScript to make it easier to debug the code.

In order to run an interactive debugger:

- `node --inspect-brk node_modules/.bin/jest --runInBand test/npm/conflicting-dependency-parser.test.js`
- In Chrome, nativate to chrome://inspect
- Click `Open dedicated DevTools for Node`
- You'll now be able to interactively debug using the chrome dev tools.
