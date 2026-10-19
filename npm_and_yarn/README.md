## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

Security PR refreshes select the vulnerable installed version, just like creation.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell npm_and_yarn
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd npm_and_yarn && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
