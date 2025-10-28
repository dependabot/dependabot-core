# Changelog

## Unreleased

### Fixed

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

- Cooldown functionality: Non-operational due to Julia registries not storing version release dates. See https://github.com/JuliaRegistries/General/issues/133593
- Custom/private registries are not yet supported
- Registry authentication is not implemented
