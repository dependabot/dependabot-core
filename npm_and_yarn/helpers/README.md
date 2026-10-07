## Native TypeScript helpers

This directory contains helper functions for npm, yarn, and pnpm, written in
TypeScript, so that we can utilize the package managers' internal APIs and other
native tooling for these ecosystems.

These helpers are called from the Ruby code via `run.ts`, they are passed
arguments via stdin and return JSON data to stdout.

## Development

Install dependencies:

```
npm install
```

### Building

The helpers are compiled from TypeScript to JavaScript before being used at
runtime. To build:

```
npm run build
```

The compiled output goes to `dist/`.

### Type checking

Run the TypeScript compiler in check-only mode (no output):

```
npm run typecheck
```

### Linting

ESLint is used for code quality checks:

```
npm run lint
```

### Formatting

Prettier is used for code formatting. To check for formatting issues:

```
npm run format
```

To auto-fix formatting:

```
npm run format:fix
```

### Testing

When working on these helpers, it's convenient to write some high level tests in
TypeScript to make it easier to debug the code.

Run the tests from this directory:

```
npm test
```

### Debugging

In order to run an interactive debugger:

- `node --inspect-brk node_modules/.bin/jest --runInBand path/to/test/test.js`
- In Chrome, navigate to `chrome://inspect`
- Click `Open dedicated DevTools for Node`
- You'll now be able to interactively debug using the Chrome dev tools.
