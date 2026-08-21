---
applyTo: "nuget/helpers/lib/NuGetUpdater/NuGetProjects/**"
---

# NuGetProjects Maintenance

## Submodule Update Checklist

When the `NuGet.Client` submodule is updated, all `*.cs` files under `NuGetProjects/` must be re-checked against their original files in the submodule to ensure they remain largely in line with the upstream content.

The NuGet version must also remain synchronized across:

- The NuGet assemblies bundled with the SDK selected by `NuGetUpdater/global.json`.
- The `release/*` branch and pinned revision for the `NuGet.Client` submodule.
- The `<Version>` in `NuGetProjects/Directory.Build.props`.
- The `Microsoft.Build` package version in `NuGetUpdater/Directory.Packages.props`.

The locally compiled NuGet assemblies and the SDK's NuGet assemblies share an assembly load context. Their assembly versions and NuGet public-key identity must match, or SDK tasks can fail at runtime with an assembly load error. `NuGetProjects/Directory.Build.targets` enforces the version relationship during builds.

## Rules for modified files

1. **No references to `NuGet.Core`.** Remove all `extern alias CoreV2` usages and any other references to the legacy `NuGet.Core` (v2) package.
2. **No .NET Framework-only APIs.** Remove or stub any APIs not compatible with .NET Core (e.g., `System.Data.Services`, WCF types, CoreV2's `PhysicalFileSystem`).
3. **Preserve behavior where possible.** When removing or stubbing, keep surrounding logic intact so the project compiles and packages.config tests pass.
4. **Document deviations.** If a file significantly diverges from upstream, add a comment at the top explaining what changed and why.
