# DependabotHelper.jl

A helper package for Dependabot to manage Julia dependencies.

This package provides the Julia-side functionality for parsing `Project.toml` and `Manifest.toml` files, resolving dependencies, and updating package versions.

## Features

- Project.toml and Manifest.toml parsing
- Dependency resolution using Julia's Pkg manager
- Version fetching from Julia registries
- Package metadata retrieval
- Update compatibility checking

## Integration

This helper is called by the Ruby-based Dependabot Julia ecosystem implementation and communicates via JSON serialization.

## Julia Documentation

For more information about Julia package management:

- [Julia Documentation](https://docs.julialang.org/en/v1/)
- [Pkg.jl Documentation](https://pkgdocs.julialang.org/v1/)

## TODOs

- [ ] Move this to its own repository and register in Julia's package registry
- [ ] Add comprehensive version history fetching from registries
