## `dependabot-pre_commit`

PreCommit support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell pre_commit
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd pre_commit && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

This ecosystem is currently under development. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

#### Required Classes
- [x] FileFetcher
- [x] FileParser
- [x] UpdateChecker
- [x] FileUpdater

#### Optional Classes
- [x] MetadataFinder
- [x] Version
- [x] Requirement

#### Supporting Infrastructure
- [x] Comprehensive unit tests
- [x] CI/CD integration
- [x] Documentation

### Additional Dependencies Support

The pre_commit ecosystem supports updating `additional_dependencies` in hooks for multiple languages (Python, Node, etc.).

#### Architecture

Additional dependencies support uses a registry pattern with two main components:

1. **Parsers** (`AdditionalDependencyParsers`) - Parse dependency strings into Dependabot::Dependency objects
2. **Checkers** (`AdditionalDependencyCheckers`) - Check for updates by delegating to ecosystem-specific UpdateCheckers

#### Adding Support for a New Language

To add support for additional_dependencies in a new language (e.g., Node, Go, Rust), follow these steps:

##### 1. Create a Parser Class

Create `lib/dependabot/pre_commit/additional_dependency_parsers/<language>.rb`:

```ruby
module Dependabot
  module PreCommit
    module AdditionalDependencyParsers
      class YourLanguage < Base
        sig { override.returns(T.nilable(Dependabot::Dependency)) }
        def parse
          # Parse dep_string (e.g., "package@1.0.0")
          # Return Dependabot::Dependency with:
          #   - name: build_dependency_name(package_name)
          #   - version: extracted_version
          #   - package_manager: "pre_commit"
          #   - source: { type: "additional_dependency", language: "...", ... }
        end
      end
    end
  end
end

# Register the language
AdditionalDependencyParsers.register("your_language", YourLanguage)
```

##### 2. Create a Checker Class

Create `lib/dependabot/pre_commit/additional_dependency_checkers/<language>.rb`:

```ruby
module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class YourLanguage < Base
        sig { override.returns(T.nilable(String)) }
        def latest_version
          # Delegate to ecosystem's UpdateChecker
          ecosystem_checker = Dependabot::UpdateCheckers
            .for_package_manager("your_package_manager")
            .new(dependency: build_ecosystem_dependency, ...)
          
          ecosystem_checker.latest_version&.to_s
        end

        sig { override.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version)
          # Return updated requirements with preserved operators
          # Preserve the original source hash from requirements
        end

        private

        def build_ecosystem_dependency
          # Create a minimal dependency that the ecosystem understands
          # Example: For npm, create package.json-style dependency
        end
      end
    end
  end
end

# Register the language
AdditionalDependencyCheckers.register("your_language", YourLanguage)
```

##### 3. Add Tests

Create spec files:
- `spec/dependabot/pre_commit/additional_dependency_parsers/<language>_spec.rb`
- `spec/dependabot/pre_commit/additional_dependency_checkers/<language>_spec.rb`

##### 4. Update Requirements

Add any ecosystem-specific requires to the parser and checker files.

#### Supported Languages

Currently supported languages for additional_dependencies:
- **Python** - Full support with PyPI version checking
- **Node** - Planned
- **Go** - Planned
- **Rust** - Planned
- **Ruby** - Planned
- **Conda** - Planned
- **Julia** - Planned

#### Key Design Principles

1. **Delegate to ecosystems** - Reuse existing UpdateCheckers instead of reimplementing version checking
2. **Preserve operators** - Maintain original version constraint operators (>=, ~=, etc.) when updating
3. **Context preservation** - Store hook/repo context in source hash for correct YAML updates
4. **Registry pattern** - Use `AdditionalDependencyParsers.for_language()` and `AdditionalDependencyCheckers.for_language()`

#### Example: Python Implementation

See `additional_dependency_parsers/python.rb` and `additional_dependency_checkers/python.rb` for reference implementations.
