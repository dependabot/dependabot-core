# Message Components Architecture

This directory contains composable message components for generating PR titles, commit messages, and PR bodies in Dependabot.

## Overview

The message components architecture provides a clean separation of concerns for building different types of messages (PR titles, PR bodies, commit messages) across different update scenarios (single dependency, grouped dependencies, multi-ecosystem updates).

## Architecture

### Base Classes

#### `MessageComponents::Base`
Abstract base class for all message components. Provides:
- Common interface with `#build` method
- Shared initialization of dependencies, source, credentials, files, etc.
- Protected accessors for all component attributes

#### `MessageComponents::PrTitle`
Base class for PR title generation. Extends `Base` and provides:
- Prefix and capitalization logic via `PrNamePrefixer`
- Security fix handling
- Directory naming
- Abstract `#base_title` method for subclasses to implement

### Concrete Implementations

#### `MessageComponents::SingleUpdateTitle`
Generates PR titles for single (non-grouped) dependency updates.

**Features:**
- Handles library vs application dependency formatting
- Supports property updates (e.g., Maven properties)
- Supports dependency set updates
- Handles multiple dependencies with the same update

**Example outputs:**
- Application: `"bump rails from 6.0 to 7.0"`
- Library: `"update rails requirement from ^6.0 to ^7.0"`
- Property: `"bump springframework.version from 4.3.12 to 4.3.15"`

#### `MessageComponents::GroupUpdateTitle`
Generates PR titles for grouped dependency updates.

**Features:**
- Reuses `SingleUpdateTitle` for single dependency in group
- Handles multi-directory updates
- Shows update count for multiple dependencies

**Example outputs:**
- Single dep: `"bump rails from 6.0 to 7.0 in the security-updates group"`
- Multiple deps: `"bump the security-updates group with 5 updates"`
- Multi-directory: `"bump the go_modules group across 3 directories with 12 updates"`

#### `MessageComponents::MultiEcosystemTitle`
Generates PR titles for multi-ecosystem grouped updates (for `dependabot-api` use).

**Features:**
- Explicitly mentions "multiple ecosystems"
- Can be used without a dependency group

**Example outputs:**
- `"bump the all-deps group with 10 updates across multiple ecosystems"`
- `"bump business in the all-deps group across multiple ecosystems"`

## Usage

### Basic Usage

```ruby
# Single dependency update
title = MessageComponents::SingleUpdateTitle.new(
  dependencies: [dependency],
  source: source,
  credentials: credentials,
  files: files,
  vulnerabilities_fixed: {},
  commit_message_options: nil,
  dependency_group: nil
)

puts title.build  # => "Bump rails from 6.0 to 7.0"

# Grouped update
group_title = MessageComponents::GroupUpdateTitle.new(
  dependencies: [dep1, dep2, dep3],
  source: source,
  credentials: credentials,
  files: files,
  vulnerabilities_fixed: {},
  commit_message_options: nil,
  dependency_group: dependency_group
)

puts group_title.build  # => "Bump the security-updates group with 3 updates"
```

### Integration with MessageBuilder

The `MessageBuilder#pr_name` method now delegates to these components:

```ruby
def pr_name
  title_component = if dependency_group
                      MessageComponents::GroupUpdateTitle.new(...)
                    else
                      MessageComponents::SingleUpdateTitle.new(...)
                    end
  
  title_component.build
end
```

### External Usage (e.g., dependabot-api)

Components can be used directly by external consumers:

```ruby
# In dependabot-api for multi-ecosystem updates
title = Dependabot::PullRequestCreator::MessageComponents::MultiEcosystemTitle.new(
  dependencies: all_dependencies,
  source: source,
  credentials: credentials,
  files: [],
  vulnerabilities_fixed: {},
  commit_message_options: nil,
  dependency_group: dependency_group
)

puts title.build  # => "Bump the all-deps group with 15 updates across multiple ecosystems"
```

## Design Principles

1. **Separation of Concerns**: Each component has a single responsibility
2. **Reusability**: Components can be used independently by any consumer
3. **Composition**: Complex components (e.g., `GroupUpdateTitle`) reuse simpler ones (e.g., `SingleUpdateTitle`)
4. **Consistency**: All titles use the same prefix/capitalization logic from `PrNamePrefixer`
5. **Type Safety**: Full Sorbet typing throughout
6. **Backward Compatibility**: `MessageBuilder` API remains unchanged

## Testing

Each component has comprehensive tests in `spec/dependabot/pull_request_creator/message_components/`:

- `single_update_title_spec.rb` - Single dependency update scenarios
- `group_update_title_spec.rb` - Grouped dependency update scenarios
- `multi_ecosystem_title_spec.rb` - Multi-ecosystem update scenarios

Tests cover:
- Single vs multiple dependencies
- Application vs library dependencies
- Directory handling
- Security vulnerability prefixes
- Property and dependency set updates
- Multi-directory updates

## Future Enhancements

The architecture is designed to support additional message components:

- `MessageComponents::PrBody` - For PR body generation
- `MessageComponents::CommitMessage` - For commit message generation
- `MessageComponents::MultiDirectoryTitle` - For multi-directory specific formatting

Each new component would:
1. Extend the appropriate base class (`Base` or `PrTitle`)
2. Implement required abstract methods
3. Be fully tested
4. Be usable independently or via `MessageBuilder`
