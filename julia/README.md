# Julia support for Dependabot

This package provides Julia support for [Dependabot](https://github.com/dependabot/dependabot-core).

It handles updates for packages managed through Julia's package manager and parses `Project.toml`/`Manifest.toml` files.

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

This implementation is designed to align with [CompatHelper.jl](https://github.com/JuliaRegistries/CompatHelper.jl), the main tool used for automated dependency updates by the Julia ecosystem (at the time of writing).

There are some notable differences:

- **Lockfile Updates**: Dependabot updates both `Project.toml` and tries to update any `Manifest.toml` files, whereas CompatHelper.jl only updates `Project.toml`.
- **Workspace Support**: Dependabot handles Julia workspaces where multiple packages share a common manifest file in a parent directory.
- **Conflict Notifications**: When manifest updates fail due to dependency conflicts (common in workspaces), Dependabot adds warning notices to pull requests explaining the issue.

Also, a goal of this is to integrate into github's CVE database and alerting systems for vulnerabilities in Julia packages.

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

## Current Limitations

- Custom/private registries are not currently fully supported
- Registry authentication is not implemented
- Full version history parsing from registries is limited
- Release date information is only available for packages in the General registry (non-General packages will not have cooldown period enforcement)

## Files Handled

- `Project.toml` / `JuliaProject.toml` - Main project files
- `Manifest.toml` / `JuliaManifest.toml` - Lock files
- `Manifest-vX.Y.toml` / `JuliaManifest-vX.Y.toml` - Version-specific lock files

### Julia Workspace Support

Julia workspaces are fully supported. In workspace configurations:

- Multiple packages can share a single manifest file located in a parent directory
- Each package has its own `Project.toml` file in a subdirectory
- The workspace root contains a manifest file (e.g., `Manifest.toml`) shared by all workspace packages
- When updating workspace packages, Dependabot will attempt to update both the individual `Project.toml` and the shared manifest
- If manifest updates fail due to conflicting requirements between workspace siblings, a warning notice is added to the pull request explaining the conflict

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
| `FileUpdater#updated_dependency_files` | `update_manifest(project_path, updates)` | Update Project.toml and Manifest.toml with comprehensive change tracking and error handling |
| **UpdateChecker** | | |
| `LatestVersionFinder#latest_version` | `get_latest_version(package_name, package_uuid)` | Find latest available non-yanked version (requires UUID) |
| **MetadataFinder** | | |
| `MetadataFinder#source_url` | `find_package_source_url(package_name, package_uuid)` | Extract repository URL from package metadata (requires UUID) |
| **PackageDetailsFetcher** | | |
| `PackageDetailsFetcher#fetch_release_dates` | `get_version_release_date(package_name, version, package_uuid)` | Get registration date for a version (General registry only) |
| `PackageDetailsFetcher#fetch_release_dates` | `batch_get_version_release_dates(packages_versions)` | Batch fetch registration dates (General registry only) |

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

**Release Date Tracking**: For packages in the General registry, release dates are fetched from the [GeneralMetadata.jl API](https://juliaregistries.github.io/GeneralMetadata.jl/). This enables Dependabot's cooldown period feature, which allows users to wait a specified number of days after a version is released before updating. Packages in other registries will not have release date information available, and cooldown periods will not apply to them.

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

## Testing with Real Repositories

For integration testing against real Julia package structures, use the [Julia-DependabotTest](https://github.com/IanButterworth/Julia-DependabotTest) repository, which contains various package configurations to validate Dependabot's behavior.

### GitHub Actions Testing

The Julia-DependabotTest repository includes a workflow to test custom dependabot-core branches or PRs:

1. Go to [Actions → Test Dependabot Julia](https://github.com/IanButterworth/Julia-DependabotTest/actions/workflows/test-dependabot.yml)
2. Click "Run workflow"
3. Enter a branch name (e.g., `ib/julia_workspaces_fixes`) or PR number (e.g., `13889`)
4. Select a test configuration
5. Results are uploaded as artifacts (`results.yaml`, `dependabot.log`)

### Local Testing

```bash
# From the dependabot-core repository root
docker build --no-cache -f Dockerfile.updater-core -t ghcr.io/dependabot/dependabot-updater-core .
docker build --no-cache -f julia/Dockerfile -t ghcr.io/dependabot/dependabot-updater-julia .

# Run against a test configuration
script/dependabot update -f /path/to/Julia-DependabotTest/dependabot-test-workspace.yaml -o results.yaml
```

