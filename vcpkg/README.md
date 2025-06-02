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

### Supported scenarios

Dependabot currently only supports updating [the `builtin-baseline` property in the `vcpkg.json` file][builtin-baseline].

### Future work

- Support updating [the `default-registry` property in the `vcpkg-configuration.json` file][default-registry].
- Support updating [the `registries` property in the `vcpkg-configuration.json` file][registries].

[core-repo]: https://github.com/dependabot/dependabot-core
[builtin-baseline]: https://learn.microsoft.com/vcpkg/reference/vcpkg-json#builtin-baseline
[default-registry]: https://learn.microsoft.com/vcpkg/reference/vcpkg-configuration-json#default-registry
[registries]: https://learn.microsoft.com/vcpkg/reference/vcpkg-configuration-json#registries
