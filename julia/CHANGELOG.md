# Changelog

## Unreleased

- Initial support for Julia dependency updates #12316
- Added Project.toml and Manifest.toml parsing
- Implemented dependency resolution via Julia's Pkg manager
- Added version fetching from Julia's General registry
- Implemented cross-platform compatibility and Docker support
- Added comprehensive test coverage

## Current Limitations

- Custom/private registries are not yet supported
- Registry authentication is not implemented
- Full version history from registries is limited to resolved versions
