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

### GitHub Actions/CI Environment

**For GitHub Actions runners (including Copilot coding agent)**, the interactive `bin/docker-dev-shell` command will NOT work. Instead, use the non-interactive CI pattern:

```bash
# Step 1: Build the ecosystem image
script/build {ecosystem}  # e.g., script/build bundler

# Step 2: Run commands inside the container (non-interactive)
docker run --rm \
  --env "CI=true" \
  --env "DEPENDABOT_TEST_ACCESS_TOKEN=$GITHUB_TOKEN" \
  ghcr.io/dependabot/dependabot-updater-{ecosystem} bash -c \
  "cd /home/dependabot/{ecosystem} && rspec spec"

# Examples for specific tasks:
# Run tests for bundler:
docker run --rm ghcr.io/dependabot/dependabot-updater-bundler bash -c \
  "cd /home/dependabot/bundler && rspec spec"

# Run rubocop for go_modules:
docker run --rm ghcr.io/dependabot/dependabot-updater-gomod bash -c \
  "cd /home/dependabot/go_modules && rubocop && rubocop -A"

# Run Sorbet type checking:
docker run --rm ghcr.io/dependabot/dependabot-updater-bundler bash -c \
  "cd /home/dependabot && bundle exec srb tc"
```

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
- **NEVER test private methods directly** - tests should only call public interfaces
- **NEVER modify production code visibility to accommodate tests** - if tests need access to private methods, the test design is wrong
- **NEVER add public methods solely for testing** - this pollutes the production API and creates maintenance burden
- Tests should verify behavior through public APIs, not implementation details
- Tests should exercise production code paths (e.g., `fetch_files`) rather than isolated helper methods

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

**Sorbet type checking workflow**:

```bash
# Run Sorbet type checker to identify errors
bundle exec srb tc

# Run type checking on specific files to focus on particular issues
bundle exec srb tc path/to/file.rb

# Use autocorrect ONLY when you have high confidence it won't cause issues
bundle exec srb tc -a path/to/file.rb
```

**Important**: Sorbet's autocorrect feature (`-a` flag) should be used cautiously as it can cause more issues than it resolves. Only use autocorrect when you have high confidence that the changes will not break code functionality.

Autocorrect can handle some simple cases like:
- Adding missing `override.` annotations for method overrides
- Adding `T.let` declarations for instance variables in strict-typed files
- Adding type annotations for constants

However, autocorrect often creates incorrect fixes for complex type mismatches, method signature issues, and structural problems. **Always manually resolve Sorbet errors** rather than relying on autocorrect, and carefully review any autocorrected changes to ensure they maintain code correctness and intent.

### Code Comments and Documentation

**Prioritize self-documenting code over comments**. Write clear, intention-revealing code with descriptive method and variable names that eliminate the need for explanatory comments.

**When to use comments**:
- **Business logic context**: Explain *why* something is done when the reason isn't obvious from the code
- **Complex algorithms**: Document the approach or mathematical concepts
- **Workarounds**: Explain why a non-obvious solution was necessary
- **External constraints**: Document API limitations, system requirements, or ecosystem-specific behaviors
- **TODO/FIXME**: Temporary markers for future improvements (with issue references when possible)

**Avoid these comment types**:
- **Implementation decisions**: Don't explain what was *not* implemented or alternative approaches considered
- **Obvious code explanations**: Don't restate what the code clearly does
- **Apologies or justifications**: Comments defending coding choices suggest code quality issues
- **Outdated information**: Remove comments that no longer apply to current implementation
- **Version history**: Use git history instead of inline change logs

**Comment style guidelines**:
```ruby
# Good: Explains WHY, adds business context
# Retry failed requests up to 3 times due to GitHub API rate limiting
retry_count = 3

# Bad: Explains WHAT the code does (obvious from code)
# Set retry count to 3
retry_count = 3

# Good: Documents external constraint
# GitHub API requires User-Agent header or returns 403
headers['User-Agent'] = 'Dependabot/1.0'

# Bad: Implementation decision discussion
# We decided not to cache this because it would complicate the code
# and other ecosystems don't do caching here either
response = fetch_data(url)
```

**Prefer code refactoring over explanatory comments**:
```ruby
# Instead of commenting complex logic:
# Calculate the SHA256 of downloaded file for security verification
digest = Digest::SHA256.hexdigest(response.body)

# Extract to a well-named method:
def calculate_security_checksum(content)
  Digest::SHA256.hexdigest(content)
end
```

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

## Core Class Structure Pattern

**CRITICAL**: All Dependabot core classes with nested helper classes must follow the exact pattern to avoid "superclass mismatch" errors. This pattern is used consistently across all established ecosystems (bundler, npm_and_yarn, go_modules, etc.).

### Main Class Structure (applies to FileFetcher, FileParser, FileUpdater, UpdateChecker, etc.)
```ruby
# {ecosystem}/lib/dependabot/{ecosystem}/file_updater.rb (or file_fetcher.rb, file_parser.rb, etc.)
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module {Ecosystem}
    class FileUpdater < Dependabot::FileUpdaters::Base
      # require_relative statements go INSIDE the class
      require_relative "file_updater/helper_class"

      # Main logic here...
    end
  end
end

Dependabot::FileUpdaters.register("{ecosystem}", Dependabot::{Ecosystem}::FileUpdater)
```

### Helper Class Structure
```ruby
# {ecosystem}/lib/dependabot/{ecosystem}/file_updater/helper_class.rb
require "dependabot/{ecosystem}/file_updater"

module Dependabot
  module {Ecosystem}
    class FileUpdater < Dependabot::FileUpdaters::Base
      class HelperClass
        # Helper logic nested INSIDE the main class
      end
    end
  end
end
```

### Key Rules:
1. **Main classes** inherit from appropriate base: `Dependabot::FileUpdaters::Base`, `Dependabot::FileFetchers::Base`, etc.
2. **Helper classes** are nested inside the main class
3. **require_relative** statements go INSIDE the main class, not at module level
4. **Helper classes require the main file** first: `require "dependabot/{ecosystem}/file_updater"`
5. **Never define multiple top-level classes** with same name in the same namespace
6. **Backward compatibility** can use static methods that delegate to instance methods

### Applies To:
- **FileFetcher** and its helpers (e.g., `FileFetcher::GitCommitChecker`)
- **FileParser** and its helpers (e.g., `FileParser::ManifestParser`)
- **FileUpdater** and its helpers (e.g., `FileUpdater::LockfileUpdater`)
- **UpdateChecker** and its helpers (e.g., `UpdateChecker::VersionResolver`)
- **MetadataFinder** and its helpers
- **Version** and **Requirement** classes (if they have nested classes)

## Adding New Ecosystems

If you are adding a new ecosystem, follow the detailed guide in `./NEW_ECOSYSTEMS.md` which provides step-by-step instructions for implementing a new package manager ecosystem.
