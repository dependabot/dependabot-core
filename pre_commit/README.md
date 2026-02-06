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

The pre_commit ecosystem provides an extensible architecture for updating `additional_dependencies` in hooks across multiple languages (Python, Node, Go, etc.).

#### Architecture Overview

The architecture uses a **registry/adapter pattern** with two main registries:

1. **AdditionalDependencyParsers** - Parses language-specific dependency strings into `Dependabot::Dependency` objects
2. **AdditionalDependencyCheckers** - Checks for version updates by delegating to ecosystem-specific `UpdateCheckers`

This pattern enables:
- **Language extensibility** - Add new language support by implementing two classes
- **Code reuse** - Delegates to existing ecosystem code (parsers, update checkers)
- **Consistent interface** - All languages follow the same pattern

#### Key Components

##### 1. Parser Registry (`AdditionalDependencyParsers`)

Registry module that manages language-specific parsers:

```ruby
# Get parser for a language
parser_class = AdditionalDependencyParsers.for_language("python")

# Check if a language is supported
AdditionalDependencyParsers.supported?("python") # => true

# List all supported languages
AdditionalDependencyParsers.supported_languages # => ["python", "node", ...]
```

##### 2. Parser Base Class (`AdditionalDependencyParsers::Base`)

Abstract base class that all language parsers must inherit from:

```ruby
class MyLanguage < AdditionalDependencyParsers::Base
  def parse
    # Parse dep_string (available via attr_reader)
    # Use helper: build_dependency_name(package_name)
    # Return Dependabot::Dependency or nil
  end
end

# Register the parser
AdditionalDependencyParsers.register("my_language", MyLanguage)
```

**Available instance variables:**
- `dep_string` - The dependency string to parse (e.g., `"package@1.0.0"`)
- `hook_id` - The pre-commit hook ID
- `repo_url` - The pre-commit hook repository URL
- `file_name` - The config file name (e.g., `.pre-commit-config.yaml`)

**Helper methods:**
- `build_dependency_name(package_name)` - Creates unique dependency name: `"#{repo_url}::#{hook_id}::#{package_name}"`

##### 3. Checker Registry (`AdditionalDependencyCheckers`)

Registry module that manages language-specific update checkers:

```ruby
# Get checker for a language
checker_class = AdditionalDependencyCheckers.for_language("python")

# Create checker instance
checker = checker_class.new(
  source: source_hash,
  credentials: credentials,
  requirements: requirements,
  current_version: "1.0.0"
)

# Check for updates
latest = checker.latest_version
updated_reqs = checker.updated_requirements(latest)
```

##### 4. Checker Base Class (`AdditionalDependencyCheckers::Base`)

Abstract base class that all language checkers must inherit from:

```ruby
class MyLanguage < AdditionalDependencyCheckers::Base
  def latest_version
    # Delegate to ecosystem's UpdateChecker
    # Return latest version string or nil
  end

  def updated_requirements(latest_version)
    # Return array of updated requirement hashes
    # Preserve original operators (>=, ~=, etc.)
  end
end

# Register the checker
AdditionalDependencyCheckers.register("my_language", MyLanguage)
```

**Available instance variables:**
- `source` - Hash containing dependency metadata from parser
- `credentials` - Array of credentials for private registries
- `requirements` - Array of requirement hashes
- `current_version` - Current version string

**Helper methods:**
- `package_name` - Extracts package name from source hash

#### Adding Support for a New Language

To add support for `additional_dependencies` in a new language, implement two classes:

**Step 1: Create Parser**

Create `lib/dependabot/pre_commit/additional_dependency_parsers/<language>.rb`:

```ruby
module Dependabot
  module PreCommit
    module AdditionalDependencyParsers
      class YourLanguage < Base
        sig { override.returns(T.nilable(Dependabot::Dependency)) }
        def parse
          # 1. Parse dep_string into components (name, version, etc.)
          # 2. Extract version using language-specific logic
          # 3. Build and return Dependabot::Dependency:
          
          Dependabot::Dependency.new(
            name: build_dependency_name(normalized_name),
            version: extracted_version,
            requirements: [{
              requirement: version_constraint,
              groups: ["additional_dependencies"],
              file: file_name,
              source: {
                type: "additional_dependency",
                language: "your_language",
                package_name: normalized_name,
                hook_id: hook_id,
                hook_repo: repo_url,
                # ... other metadata ...
              }
            }],
            package_manager: "pre_commit"
          )
        end
      end
    end
  end
end

AdditionalDependencyParsers.register("your_language", YourLanguage)
```

**Step 2: Create Checker**

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
            .new(
              dependency: build_ecosystem_dependency,
              dependency_files: build_dependency_files,
              credentials: credentials,
              # ...
            )
          
          ecosystem_checker.latest_version&.to_s
        end

        sig { override.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version)
          # Build updated requirements preserving operators
          requirements.map do |req|
            req.merge(
              requirement: build_updated_constraint(req[:requirement], latest_version)
            )
          end
        end

        private

        def build_ecosystem_dependency
          # Create minimal dependency that ecosystem understands
        end
      end
    end
  end
end

AdditionalDependencyCheckers.register("your_language", YourLanguage)
```

**Step 3: Add Tests**

Create spec files:
- `spec/dependabot/pre_commit/additional_dependency_parsers/<language>_spec.rb`
- `spec/dependabot/pre_commit/additional_dependency_checkers/<language>_spec.rb`

#### Design Principles

1. **Delegate to ecosystems** - Reuse existing `FileParser`, `UpdateChecker`, `Requirement` classes instead of reimplementing
2. **Preserve operators** - Maintain original version constraint operators (>=, ~=, ==) when updating
3. **Context preservation** - Store hook/repo context in source hash for correct YAML updates
4. **Registry pattern** - Use `.for_language()` and `.register()` for extensibility
5. **Minimal custom code** - Only implement glue logic between pre-commit YAML and ecosystem formats

#### Supported Languages

Currently supported languages for additional_dependencies:
- **Python** 
- **Node**
- **Go**
- **Rust**
- **Ruby**
- **Conda**
- **Julia**
- **Dart**

#### Integration Points

The architecture integrates with pre_commit's core classes:

- **FileParser** - Uses `AdditionalDependencyParsers.for_language()` to parse dependencies
- **UpdateChecker** - Uses `AdditionalDependencyCheckers.for_language()` to check for updates
- **FileUpdater** - Updates YAML using context from dependency source hash
