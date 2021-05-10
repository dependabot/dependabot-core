Native JavaScript helpers
-------------------------

This directory contains helper functions for npm and yarn, natively written in
Javascript so that we can utilize the package managers internal APIs and other
native tooling for these ecosystems.

These helpers are called from the Ruby code via `run.js`, they are passed
arguments via stdin and return JSON data to stdout.

## Testing

When working on these helpers, it's convenient to write some high level tests in
JavaScript to make it easier to debug the code.

You can now run the tests from this directory by running:

```
yarn test path/to/test.js
```

### Debugging

In order to run an interactive debugger:

- `node --inspect-brk node_modules/.bin/jest --runInBand path/to/test/test.js`
- In Chrome, nativate to chrome://inspect
- Click `Open dedicated DevTools for Node`
- You'll now be able to interactively debug using the chrome dev tools.
