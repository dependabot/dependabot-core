## `dependabot-vcpkg`

VCPKG support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  bin/docker-dev-shell vcpkg
  ```

1. Run tests

   ```
   [dependabot-core-dev] ~ $ cd vcpkg && rspec
   ```

### Supported scenarios

- Updating [the `builtin-baseline` property in the `vcpkg.json` file][builtin-baseline].
- Updating [the `default-registry` and `registries` properties in the `vcpkg-configuration.json` file][default-registry].
- Updating a port's [`version>=` constraint][version-gte].
- Security updates for ports, driven by advisories under the `vcpkg` OSV ecosystem.

### Security updates

A port's version comes from its `version>=` constraint, from the registry baseline, or from both. vcpkg installs the lowest version that satisfies every constraint, so Dependabot works out the effective version by reading `versions/baseline.json` at the commit the manifest pins. That is what gives a bare string dependency a version to test an advisory against.

There are three ways to move a vulnerable port, and Dependabot takes the first one that works:

1. Raise the baseline to the oldest vcpkg release tag whose version floor for the port is safe. Where the baseline is what picks the version, that is the whole fix.
2. Raise the `version>=` constraint. This covers the case where no release carries the fix yet. A port declared as a bare string becomes an object so it can hold the constraint.
3. Add an `overrides` entry. [vcpkg refuses to compare versions across schemes][version-schemes], so if every safe version was published under a different scheme than the one in use, pinning the port outright is the only option left.

The versions database and the release tags both come from the vcpkg checkout at `VCPKG_ROOT` (`/opt/vcpkg` in the updater image). Dependabot fetches it first, so a version published since the image was built is still visible.

#### Limitations

- Transitive ports are left alone. Dependabot can only edit what the manifest declares.
- Dependabot skips ports that come from any registry other than the built-in one, because the shipped versions database says nothing about them.
- A port pinned to a bare commit SHA does not count as versioned, which keeps a registry baseline recognizable as a git SHA. That affects a handful of pre-2018 `version-string` entries.

### Future work

- Handle transitive ports, most likely by reading a `vcpkg install --dry-run` plan.

[core-repo]: https://github.com/dependabot/dependabot-core
[builtin-baseline]: https://learn.microsoft.com/vcpkg/reference/vcpkg-json#builtin-baseline
[default-registry]: https://learn.microsoft.com/vcpkg/reference/vcpkg-configuration-json#default-registry
[version-gte]: https://learn.microsoft.com/vcpkg/users/versioning#version-gte
[version-schemes]: https://learn.microsoft.com/vcpkg/users/versioning#version-schemes
