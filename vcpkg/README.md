## `dependabot-vcpkg`

VCPKG support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell vcpkg
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd vcpkg && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
