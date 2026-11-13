## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Node.js versions

The updater selects Node from the update directory's `.nvmrc`, then `.node-version`,
then `package.json`'s `engines.node`. It also considers `devEngines.runtime`:

- With `onFail: "error"`, omitted, or `"download"`, both requirements must match;
  neither overrides the other, and conflicts fail the update.
- With `"warn"` or `"ignore"`, try to satisfy both, but the version-file or
  `engines.node` requirement wins if that is not possible.

Runtime arrays are alternatives, with the last entry's `onFail` applying as in npm.
The image's default Node is retained when compatible; otherwise nvm downloads the
highest matching stable release. Ranges use npm semver; version files also support
`node`, `stable`, `lts/*`, and `lts/<codename>`.

Package-manager versions and native-helper Node are unchanged. Package managers
still enforce their own engine checks, so incompatible tooling can fail an update.
Runtime selection requires the image's nvm installation and `NVM_DIR`.

`NVM_NODEJS_ORG_MIRROR` defaults to `https://nodejs.org/dist` and can be set as a
Docker build argument or container environment variable. The mirror must be
accessible through the updater's proxy and provide Node's `index.tab`, release
archives, and `SHASUMS256.txt`.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell npm_and_yarn
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd npm_and_yarn && rspec
   ```

   Runtime integration specs require `DEPENDABOT_TEST_NODE_18` and
   `DEPENDABOT_TEST_NODE_22` to point to installed Node directories; they skip
   locally when unset.

[core-repo]: https://github.com/dependabot/dependabot-core
