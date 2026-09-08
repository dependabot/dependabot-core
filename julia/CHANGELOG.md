# Changelog

## Unreleased

### Added

- Added support for Julia workspaces (multiple packages sharing a common manifest file)
- Added warning notices to PRs when manifest updates fail due to dependency conflicts
- Added absolute path resolution for workspace manifests in user-facing notices

### Changed

- Pinned the updater image to the Julia 1.13 release channel instead of juliaup's default `release` channel
- Simplified file updater architecture to work directly in temporary repo directory instead of nested temporary directories
- Improved manifest update error handling with detailed user notifications

### Fixed

- Fixed registry lookups on Julia 1.13, where Pkg changed `registry_info` to also take the registry instance
- Stop adding or updating compat entries for standard libraries that also have registry releases (legacy bridge packages such as `Artifacts`, upgradable stdlibs such as `Statistics`); whether a dependency is a stdlib is decided per Julia release across the project's `julia` compat range using HistoricalStdlibVersions.jl (#16227, #16228)
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
