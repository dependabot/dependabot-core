# Julia support for Dependabot

This package provides Julia support for [Dependabot](https://github.com/dependabot/dependabot-core).

It handles updates for packages managed through Julia's package manager and parses `Project.toml`/`Manifest.toml` files.

**For developers:** See [DEVDOCS.md](DEVDOCS.md) for detailed architecture and implementation information.

## Supported Features

- Parsing of `Project.toml` and `Manifest.toml` files
- Version resolution and dependency updates
- Support for standard Julia semantic versioning
- Integration with Julia's General registry
- Cross-platform compatibility
- Release date tracking for packages in the General registry (enables cooldown period feature)
- Julia workspace support (packages with shared manifest files)
- User notifications when manifest updates fail due to dependency conflicts

## Comparison to CompatHelper.jl

Dependabot’s Julia updater follows the same compatibility rules as [CompatHelper.jl](https://github.com/JuliaRegistries/CompatHelper.jl) while offering a few additional behaviours:

- **Lockfile updates** – Dependabot always attempts to regenerate `Manifest.toml`, whereas CompatHelper focuses on `Project.toml` only.
- **Workspace awareness** – shared manifests in parent directories are fetched once and included in every PR that touches workspace members.
- **Conflict notices** – when the Julia resolver cannot update a manifest, Dependabot adds an explicit warning to the pull request so users understand why only the project file changed.

## Julia Documentation References

For more information about Julia package management, see:

- [Julia Documentation](https://docs.julialang.org/en/v1/)
- [Pkg.jl Documentation](https://pkgdocs.julialang.org/v1/)
- [Project.toml and Manifest.toml format](https://pkgdocs.julialang.org/v1/toml-files/)
- [Julia semantic versioning](https://pkgdocs.julialang.org/v1/compatibility/)

## Error Handling and User Notifications

When manifest updates fail (common in workspace configurations with conflicting sibling dependencies), Dependabot will:

1. Successfully update the `Project.toml` file with the new dependency requirements
2. Attempt to update the corresponding manifest file using Julia's package resolver
3. If the manifest update fails due to conflicts, add a warning notice to the pull request describing:
   - Which manifest file could not be updated (with absolute path for clarity)
   - The specific error message from Julia's package resolver
   - The fact that only the `Project.toml` was updated

This ensures users understand when lockfiles couldn't be updated and why, while still providing the compatibility range update in the project file.

## Julia Workspace Support

Julia workspaces allow multiple packages to share a common `Manifest.toml` file in a parent directory. Dependabot fully supports this pattern:

**Supported Structure:**

```text
WorkspaceRoot/
├── Manifest.toml          # Shared lockfile
├── SubPackageA/
│   └── Project.toml       # Package-specific dependencies
└── SubPackageB/
    └── Project.toml       # Package-specific dependencies
```

**How it works:**

- Dependabot uses Julia's `Pkg` to discover workspace manifests in parent directories.
- Each subdirectory can be listed separately in `dependabot.yml`.
- Updates to dependencies in any workspace member update the shared `Manifest.toml`.
- The pull request includes the changed `Project.toml` files and the shared manifest.
- If the manifest fails to update because of conflicting requirements, Dependabot adds a warning notice to the PR summarising the resolver error.

**Example dependabot.yml:**

```yaml
updates:
  - package-ecosystem: "julia"
    directories:
      - "/WorkspaceRoot/SubPackageA"
      - "/WorkspaceRoot/SubPackageB"
    schedule:
      interval: "weekly"
```

## Files Handled

- `Project.toml` / `JuliaProject.toml` - Main project files
- `Manifest.toml` / `JuliaManifest.toml` - Lock files
- `Manifest-vX.Y.toml` / `JuliaManifest-vX.Y.toml` - Version-specific lock files

### Terminology Note

**Important**: There is a terminology difference between Julia and Dependabot ecosystems:

| File | Julia Terminology | Dependabot Terminology |
|------|-------------------|-------------------------|
| `Project.toml` | "Project file" | "Manifest file" / "Package manifest" / "Dependency manifest" |
| `Manifest.toml` | "Manifest file" | "Lockfile" |

This documentation uses Julia terminology for consistency with the ecosystem.

## Current Limitations

- Custom/private registries are not currently fully supported
- Registry authentication is not implemented
- Full version history parsing from registries is limited
- Release date information is only available for packages in the General registry (non-General packages will not have cooldown period enforcement)
