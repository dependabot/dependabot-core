# Julia support for Dependabot

This package provides Julia support for [Dependabot](https://github.com/dependabot/dependabot-core).

It handles updates for packages managed through Julia's package manager and parses `Project.toml`/`Manifest.toml` files.

## Supported Features

- Parsing of `Project.toml` and `Manifest.toml` files
- Version resolution and dependency updates
- Support for standard Julia semantic versioning
- Integration with Julia's General registry
- Cross-platform compatibility

## Julia Documentation References

For more information about Julia package management, see:

- [Julia Documentation](https://docs.julialang.org/en/v1/)
- [Pkg.jl Documentation](https://pkgdocs.julialang.org/v1/)
- [Project.toml and Manifest.toml format](https://pkgdocs.julialang.org/v1/toml-files/)
- [Julia semantic versioning](https://pkgdocs.julialang.org/v1/compatibility/)

## Current Limitations

- Custom/private registries are not currently fully supported
- Registry authentication is not implemented
- Full version history parsing from registries is limited

## Files Handled

- `Project.toml` / `JuliaProject.toml` - Main project files
- `Manifest.toml` / `JuliaManifest.toml` - Lock files
- `Manifest-vX.Y.toml` / `JuliaManifest-vX.Y.toml` - Version-specific lock files

### Terminology: Julia vs Dependabot

**Important**: There is a terminology difference between Julia and Dependabot ecosystems:

| File | Julia Terminology | Dependabot Terminology |
|------|-------------------|-------------------------|
| `Project.toml` | "Project file" | "Manifest file" / "Package manifest" / "Dependency manifest" |
| `Manifest.toml` | "Manifest file" | "Lockfile" |

**Implications for development:**

- This Julia helper maintains Julia terminology internally (e.g., `parse_project`, `parse_manifest`)
- When interfacing with Dependabot Ruby code, be aware that they use different terms for the same files
- Documentation and error messages use Julia terminology for consistency with the ecosystem

## Implementation Approach

The Julia ecosystem implementation follows a hybrid approach where the Ruby infrastructure handles Dependabot's core workflow, while the complex Julia-specific logic is implemented in Julia itself via the `DependabotHelper.jl` package.

### Architecture Overview

```text
┌─────────────────┐    JSON-RPC    ┌─────────────────────┐
│                 │ ─────────────► │                     │
│ Ruby Classes    │                │ DependabotHelper.jl │
│ (Dependabot)    │ ◄───────────── │ (Julia Package)     │
│                 │                │                     │
└─────────────────┘                └─────────────────────┘
```

**Why this approach?**

- **Leverage Julia's Pkg ecosystem**: Julia's package manager and type system are complex, and reimplementing them in Ruby would be error-prone and difficult to maintain
- **Native dependency resolution**: Use Julia's built-in `Pkg.jl` for accurate dependency resolution and version constraints
- **Future-proof**: Stay aligned with Julia ecosystem changes by using the official package manager APIs

### Ruby-to-Julia Function Mapping

| Ruby Class/Method | Julia Function | Purpose |
|-------------------|----------------|---------|
| **FileParser** | | |
| `FileParser#project_file_dependencies` | `parse_project(project_path, manifest_path)` | Parse Project.toml and extract dependencies with resolved versions |
| **RegistryClient** | | |
| `RegistryClient#fetch_latest_version` | `get_latest_version(package_name, package_uuid)` | Get latest non-yanked version from Julia registry (requires UUID) |
| `RegistryClient#fetch_package_metadata` | `get_package_metadata(package_name, package_uuid)` | Get comprehensive package information (requires UUID) |
| `RegistryClient#parse_project` | `parse_project(project_path, manifest_path)` | Project parsing with metadata |
| `RegistryClient#parse_manifest` | `parse_manifest(manifest_path)` | Parse Manifest.toml files |
| `RegistryClient#get_version_from_manifest` | `get_version_from_manifest(manifest_path, name, uuid)` | Extract specific package version from manifest (requires UUID) |
| **FileUpdater** | | |
| `FileUpdater#updated_dependency_files` | `update_manifest(project_path, updates)` | Update Project.toml and Manifest.toml with comprehensive change tracking |
| **UpdateChecker** | | |
| `LatestVersionFinder#latest_version` | `get_latest_version(package_name, package_uuid)` | Find latest available non-yanked version (requires UUID) |
| **MetadataFinder** | | |
| `MetadataFinder#source_url` | `find_package_source_url(package_name, package_uuid)` | Extract repository URL from package metadata (requires UUID) |

### Communication Protocol

Ruby classes communicate with Julia functions via:

1. **SharedHelpers.run_helper_subprocess**: Launches Julia with the DependabotHelper.jl project
2. **JSON serialization**: Function arguments and return values are serialized as JSON
3. **Error handling**: Julia exceptions are caught and returned as error objects to Ruby
4. **Environment setup**: Julia depot path and registry credentials are configured via environment variables

### Key Implementation Details

**UUID Enforcement**: All package lookup functions require both package name and UUID for precise identification. This eliminates ambiguity when multiple packages have similar names and ensures registry lookups are deterministic.

**Yanked Version Exclusion**: The `get_latest_version` function automatically excludes yanked versions from consideration by checking the `yanked` flag in the registry's version metadata, ensuring only stable, non-retracted versions are returned.

**Error Handling**: When all versions of a package are yanked, the function returns a descriptive error message rather than failing silently.

### Julia Helper Structure

```text
julia/helpers/DependabotHelper.jl/
├── src/
│   ├── DependabotHelper.jl     # Main module
│   ├── functions.jl            # Core dependency management functions
│   └── precompile.jl          # Precompilation setup
├── test/                       # Test package for precompilation
└── run_dependabot_helper.jl    # Entry point script
```

The `run_dependabot_helper.jl` script acts as the JSON-RPC server, receiving function calls from Ruby and dispatching them to the appropriate Julia functions.

