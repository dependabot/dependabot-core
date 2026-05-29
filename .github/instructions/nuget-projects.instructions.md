---
applyTo: "nuget/helpers/lib/NuGetUpdater/NuGetProjects/**"
---

# NuGetProjects Maintenance

## Submodule Update Checklist

When the `NuGet.Client` submodule is updated, all `*.cs` files under `NuGetProjects/` must be re-checked against their original files in the submodule to ensure they remain largely in line with the upstream content.

## Rules for modified files

1. **No references to `NuGet.Core`.** Remove all `extern alias CoreV2` usages and any other references to the legacy `NuGet.Core` (v2) package.
2. **No .NET Framework-only APIs.** Remove or stub any APIs not compatible with .NET Core (e.g., `System.Data.Services`, WCF types, CoreV2's `PhysicalFileSystem`).
3. **Preserve behavior where possible.** When removing or stubbing, keep surrounding logic intact so the project compiles and packages.config tests pass.
4. **Document deviations.** If a file significantly diverges from upstream, add a comment at the top explaining what changed and why.
