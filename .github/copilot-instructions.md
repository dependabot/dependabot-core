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
- `updater/` - Service layer that orchestrates the update process
- `script/` - Build and development scripts

**Note**: When working in containers, the `updater/` folder is renamed to `dependabot-updater/`. This affects test paths and file references inside the container.

## Development Workflow

### Local Development Setup

```bash
# Step 1: Start the Docker development environment for a specific ecosystem
bin/docker-dev-shell {ecosystem}  # e.g., go_modules, bundler
# This opens an interactive shell inside the container
```

**Note**: The first run of `bin/docker-dev-shell` can take some minutes as it builds the Docker development image from scratch. Wait for it to complete before proceeding. Check for completion every 5 seconds. Subsequent runs will be much faster as they reuse the built image.

### Testing Changes

**IMPORTANT**: All testing must be done within Docker containers. The development environment, dependencies, and native helpers are containerized and will not work on the host system.

**Workflow**: First start the container with `bin/docker-dev-shell {ecosystem}`, then run commands within the interactive container shell:

```bash
# Step 1: Start the container (from host)
bin/docker-dev-shell bundler

# Step 2: Run commands inside the container shell
cd {ecosystem} && rspec spec  # Run ecosystem tests
rubocop                       # Check code style
rubocop -A                    # Auto-fix code style issues (if any found)
bundle exec srb tc            # Run Sorbet type checking

# For updater tests, note the folder name change in containers
cd dependabot-updater && rspec spec  # Run updater tests (not cd updater)

# Test changes with real repositories
bin/dry-run.rb {ecosystem} {repo} --dep="specific-dependency"

# After making changes, run the full validation suite:
bundle exec tapioca gem --verify  # Verify gem type definitions
bundle exec srb tc               # Type check all files
rubocop                          # Code style check
rubocop -A                       # Auto-fix any code style issues
rspec spec                       # Run relevant tests
```

**Test Coverage Requirements**:

- All changes must be covered by tests - this is critical to prevent regressions
- All existing tests must continue to pass after your changes
- Add tests for new functionality before implementing the feature
- When fixing bugs, add a test that reproduces the issue first

### Code Style and Validation

After making changes, run the full validation suite:

```bash
bundle exec tapioca gem --verify  # Verify gem type definitions
bundle exec srb tc               # Type check all files
rubocop                          # Code style check
rubocop -A                       # Auto-fix any code style issues (if any found)
rspec spec                       # Run relevant tests
```

**Important**: Always use `rubocop -A` to automatically fix code style issues when they can be auto-corrected. This ensures consistent formatting and reduces manual work.

### RuboCop Best Practices

**Avoid adding RuboCop exceptions** unless absolutely necessary. The default approach should be to resolve offenses using proper coding practices:

- **Method extraction**: Break large methods into smaller, focused methods
- **Class extraction**: Split large classes into smaller, single-responsibility classes
- **Reduce complexity**: Simplify conditional logic and nested structures
- **Improve naming**: Use clear, descriptive variable and method names
- **Refactor long parameter lists**: Use parameter objects or configuration classes
- **Extract constants**: Move magic numbers and strings to named constants

**If a RuboCop exception is truly unavoidable**, provide clear justification in a comment explaining why the rule cannot be followed and what alternative approaches were considered.

### Sorbet Type Checking

**All new files must be Sorbet strict typed at minimum**. When updating existing files with lower typing levels, increase the typing to at least `strict`:

```ruby
# typed: strict
# frozen_string_literal: true
```

**Typing level requirements**:

- **New files**: Must use `# typed: strict` or higher
- **Existing files**: If below `strict`, upgrade to `# typed: strict` when making changes
- **Type annotations**: Add explicit type signatures for method parameters and return values
- **Validation**: Always run `bundle exec srb tc` to ensure type correctness

### Native Helpers

Many ecosystems use native language helpers (Go, Node.js, Python) located in `{ecosystem}/helpers/`. These helpers run exclusively within containers and changes require rebuilding:

```bash
# Inside dev container - native helpers only work in containerized environment
{ecosystem}/helpers/build  # Rebuild native helpers
```

**Note**: Native helper changes are not automatically reflected in the container. You must rebuild them after any modifications.

## Key Patterns & Conventions

### Error Handling

- Use ecosystem-specific error classes that inherit from `Dependabot::DependabotError`
- Native helper failures should be caught and wrapped in Ruby exceptions
- Network timeouts and rate limits are handled by the `common` layer

### File Handling

- Always use `Dependabot::DependencyFile` objects, never raw file content
- Files have `name`, `content`, `directory`, and `type` attributes
- Support both manifest files (e.g., `package.json`) and lockfiles (e.g., `package-lock.json`)

### Version Comparison

- Implement ecosystem-specific `Version` classes that handle pre-releases, build metadata
- Example: `Dependabot::GoModules::Version` handles Go's semantic versioning with `+incompatible` suffix

### Docker Architecture

Each ecosystem has a layered Docker structure:
```
dependabot-updater-{ecosystem} (contains native tools like npm, pip)
├── dependabot-updater-core (Ruby runtime + common dependencies)
```

## Testing Patterns

### Fixture-Based Testing

```ruby
# Use real dependency files as fixtures
let(:dependency_files) { bundler_project_dependency_files("example_project") }

# Helper methods in spec_helper.rb generate realistic test data
```

### Mocking External Calls

- Mock HTTP requests to package registries using VCR or WebMock
- Test with realistic registry responses to catch edge cases

## Integration Points

### Security Updates

Handle `SECURITY_ADVISORIES` environment variable for vulnerability-driven updates that target minimum safe versions rather than latest versions.

### Private Registries

Support private registry credentials through the credential proxy pattern - never store credentials in Dependabot Core directly.

### Cross-Platform Support

- **All code must run in Docker containers on Linux** - dependencies, testing, and development environments are containerized
- Native helpers must support the container's architecture
- Use `SharedHelpers.in_a_temporary_repo_directory` for file operations
- **Never attempt to run tests or native helpers on the host system** - they will fail outside containers

## Common Debugging Commands

```bash
# Debug with breakpoints
DEBUG_HELPERS=true bin/dry-run.rb {ecosystem} {repo}

# Debug specific native helper functions
DEBUG_FUNCTION=function_name bin/dry-run.rb {ecosystem} {repo}

# Profile performance
bin/dry-run.rb {ecosystem} {repo} --profile
```

**Note**: All debugging commands must be run within the development container after starting it with `bin/docker-dev-shell {ecosystem}`.

## File Naming Conventions

- Main classes: `{ecosystem}/lib/dependabot/{ecosystem}/file_fetcher.rb`
- Tests: `{ecosystem}/spec/dependabot/{ecosystem}/file_fetcher_spec.rb`
- Fixtures: `{ecosystem}/spec/fixtures/`
- Native helpers: `{ecosystem}/helpers/`

When implementing new ecosystems or modifying existing ones, always ensure the 7 core classes are implemented and follow the established inheritance patterns from `dependabot-common`.

## Adding New Ecosystems

If you are adding a new ecosystem, follow the detailed guide in `./NEW_ECOSYSTEMS.md` which provides step-by-step instructions for implementing a new package manager ecosystem.
