# Dependabot Core AI Agent Instructions

## Architecture Overview

Dependabot Core is a modular Ruby gem collection that updates dependencies across 20+ ecosystems. The architecture follows a plugin pattern where each package manager (e.g., `go_modules`, `bundler`, `npm_and_yarn`) implements the same core interfaces.

### Core Components

Each ecosystem implements these 7 required classes that inherit from `dependabot-common` base classes:
- **FileFetcher**: Downloads dependency files (e.g., `go.mod`, `package.json`)
- **FileParser**: Extracts dependencies from manifest files
- **UpdateChecker**: Determines if updates are available
- **FileUpdater**: Generates updated dependency files
- **MetadataFinder**: Retrieves dependency metadata (GitHub URLs, changelogs)
- **Version**: Handles version comparison logic
- **Requirement**: Parses dependency requirement formats

### Monorepo Structure

- `common/` - Shared base classes and utilities used by all ecosystems
- `{ecosystem}/` - Each directory contains a complete gem (e.g., `go_modules/`, `bundler/`)
- `omnibus/` - Meta-gem that includes all ecosystem gems
- `updater/` - Service layer that orchestrates the update process (renamed to `dependabot-updater/` inside containers)
- `script/` - Build and development scripts

## Key Patterns & Conventions

### Error Handling

- Use ecosystem-specific error classes inheriting from `Dependabot::DependabotError`
- Catch native helper failures and wrap them in Ruby exceptions
- Network timeouts and rate limits are handled by the `common` layer

### File Handling

- Always use `Dependabot::DependencyFile` objects, never raw file content
- Files have `name`, `content`, `directory`, and `type` attributes
- Support both manifest files (e.g., `package.json`) and lockfiles (e.g., `package-lock.json`)

### Version Comparison

- Implement ecosystem-specific `Version` classes for pre-releases, build metadata, etc.
- Example: `Dependabot::GoModules::Version` handles Go semver with `+incompatible` suffix

### Docker Architecture

Each ecosystem has a layered Docker structure:
```
dependabot-updater-{ecosystem} (contains native tools like npm, pip)
├── dependabot-updater-core (Ruby runtime + common dependencies)
```

All code runs in Docker containers on Linux. Never run tests or native helpers on the host system.

## File Naming Conventions

- Main classes: `{ecosystem}/lib/dependabot/{ecosystem}/file_fetcher.rb`
- Tests: `{ecosystem}/spec/dependabot/{ecosystem}/file_fetcher_spec.rb`
- Fixtures: `{ecosystem}/spec/fixtures/`
- Native helpers: `{ecosystem}/helpers/`

When implementing or modifying ecosystems, ensure the 7 core classes are implemented and follow the inheritance patterns from `dependabot-common`.

## Integration Points

### Security Updates

Handle `SECURITY_ADVISORIES` for vulnerability-driven updates that target minimum safe versions rather than latest.

### Private Registries

Support private registry credentials through the credential proxy pattern — never store credentials in Dependabot Core directly.

### Cross-Platform

- Use `SharedHelpers.in_a_temporary_repo_directory` for file operations
- Native helpers must support the container's architecture

## PR Workflow

- After addressing PR review feedback, always resolve the corresponding review threads on the PR.

## Adding New Ecosystems

Follow the detailed guide in `./NEW_ECOSYSTEMS.md` for step-by-step instructions on implementing a new package manager ecosystem.
