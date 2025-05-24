# Changelog

## Unreleased

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
