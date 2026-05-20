# NuGetProjects

This directory contains locally-compiled versions of projects from the [NuGet.Client](https://github.com/NuGet/NuGet.Client) submodule. The `*.cs` files here are either copied directly from or are modified replacements of files in the vendored submodule source.

## Maintenance: Submodule Updates

Whenever the `NuGet.Client` submodule is updated, **all `*.cs` files under this directory must be re-checked** against their corresponding originals in the submodule to ensure they remain largely in line with the upstream content.

### Rules for modified files

1. **No references to the `NuGet.Core` package.** All `extern alias CoreV2` usages and any other references to the legacy `NuGet.Core` (v2) package must be removed.
2. **No .NET Framework-only APIs.** Any APIs that are not compatible with .NET Core / modern .NET (e.g., `System.Data.Services`, WCF types, `PhysicalFileSystem` from CoreV2) must be removed or stubbed.
3. **Keep behavior parity where possible.** When removing or stubbing functionality, preserve the surrounding logic so that the project continues to compile and the packages.config update tests continue to pass.
4. **Document deviations.** If a file diverges significantly from its upstream counterpart, add a comment at the top of the file explaining what was changed and why.
