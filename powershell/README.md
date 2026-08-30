## `dependabot-powershell`

PowerShell support for [`dependabot-core`][core-repo].

### Supported dependency declarations

Dependabot updates PowerShell module specifications declared in:

- `#Requires -Modules` directives in `.ps1` and `.psm1` files
- `using module` statements in `.ps1` and `.psm1` files
- `RequiredModules` entries in `.psd1` module manifests
- Versioned external `NestedModules` entries in `.psd1` module manifests

Local module paths and unversioned nested components are left unchanged.

### Registries

Module versions are resolved from the Microsoft Artifact Registry (MAR) first, matching PowerShell's repository priority. When a module is not present in MAR, Dependabot falls back to the PowerShell Gallery. An operational or malformed MAR response does not fall back, which prevents an untrusted package with the same name from replacing a Microsoft-hosted module.

MAR does not expose package publication timestamps through its OCI manifests. When a configured cooldown applies to a MAR-hosted module, Dependabot leaves that module unchanged rather than bypassing the cooldown. PowerShell Gallery releases continue to use their published timestamps for cooldown filtering.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell powershell
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd powershell && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

This ecosystem is currently under development. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

#### Required Classes
- [x] FileFetcher
- [x] FileParser
- [x] UpdateChecker
- [x] FileUpdater

#### Optional Classes
- [x] MetadataFinder
- [x] Version
- [x] Requirement

#### Supporting Infrastructure
- [x] Comprehensive unit tests
- [x] CI/CD integration
- [ ] Documentation
