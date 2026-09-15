# Changelog

## Unreleased

### Added

- Added support for Julia workspaces (multiple packages sharing a common manifest file)
- Added warning notices to PRs when manifest updates fail due to dependency conflicts
- Added absolute path resolution for workspace manifests in user-facing notices
- `[extras]` packages that already have a `[compat]` entry now get compat updates, matching CompatHelper.jl's default `IfExistingCompatExtras()` policy; they are reported as development dependencies

### Changed

- Pinned the updater image to the Julia 1.13 release channel instead of juliaup's default `release` channel
- Simplified file updater architecture to work directly in temporary repo directory instead of nested temporary directories
- Improved manifest update error handling with detailed user notifications

### Fixed

- Fixed registry lookups on Julia 1.13, where Pkg changed `registry_info` to also take the registry instance
- Fixed suggested `[compat]` entries for JLL packages carrying the build number (e.g. `Zlib_jll = "1.6.10+0"`), which Pkg rejects as an invalid version specifier
- A JLL rebuild (`0.0.43+1`) now satisfies a compat entry admitting `0.0.43`, as it does for Pkg, instead of proposing a redundant `=0.0.43, 0.0.43` widening; prerelease tags are ignored the same way, so `2.0.0-rc1` is not taken as admitted by `"1"`
- Weakdeps and extras that appear in the manifest as indirect dependencies no longer get a manifest version, which announced a version bump the manifest update then refused to apply
- Compat entries for standard libraries are now derived from the versions bundled across the project's `julia` compat range (using HistoricalStdlibVersions.jl) instead of the latest registry release, which produced bounds like `Artifacts = "1.3.0"` from a legacy bridge package or `Statistics = "1.11.5"` from an upgradable stdlib release; stdlib entries are only ever widened and their manifest entries are left alone (#16227, #16228)
- Stdlib compat entries of a workspace environment (`test/`, `docs/`, ...) are now derived from the Julia range Pkg resolves the workspace under, the intersection of every workspace project's `julia` entry, and those of a package's `test/` environment outside a workspace from the package's entry; an environment without a `julia` entry was treated as supporting every Julia release, producing floors like `Statistics = "0.0.0, 1"` in `test/Project.toml`. Packages keep using their own entry since they are also installed on their own
- Fixed Julia version requirement parsing to correctly handle caret (^) and tilde (~) semantics according to Julia's official specification
- Fixed handling julia style compat version spec lists
- Corrected test expectations for 0.0.x version semantics to match Julia Pkg behavior (0.0.5 satisfies only itself, not 0.0.6+)

### Initial Release

- Initial support for Julia dependency updates (#12316)
- Added Project and Manifest toml file parsing
- Implemented dependency resolution via Julia's Pkg manager
- Added version fetching from Julia's General registry
- Implemented cross-platform compatibility and Docker support
- Added comprehensive test coverage

## Current Limitations

- Release date information is only available for packages in the General registry (packages in custom registries will not have cooldown period enforcement)
- Registry authentication is not implemented
