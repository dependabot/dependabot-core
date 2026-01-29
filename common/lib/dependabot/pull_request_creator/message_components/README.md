# Message Components Architecture

## The Problem

**PR title generation was duplicated between dependabot-core and dependabot-api**, causing inconsistency and maintenance overhead:

1. **Single/group ecosystem titles** → Built in `MessageBuilder` (dependabot-core)
2. **Multi-ecosystem titles** → Built separately in dependabot-api with different logic
3. **Result**: 
   - Different implementations with subtle inconsistencies
   - Duplicated prefix/capitalization logic
   - Hard to maintain consistency across both systems

### Related Issues

- PR #14045 attempts to extract shared PR title construction but only partially
- PR github/dependabot-api#7686 duplicates prefix logic in API layer

## The Solution

This directory contains **composable message components** that can be used by both dependabot-core and dependabot-api, providing:

- **Single source of truth** for PR title generation
- **Consistent formatting** (prefix, capitalization, security markers)
- **Reusable components** that API can import directly
- **Clean separation of concerns** for different update types

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

### For dependabot-core (Internal)

The `MessageBuilder` uses components internally:

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

### For dependabot-api (External Consumer)

**This is the key use case** - dependabot-api can now use the same components:

```ruby
# In dependabot-api for multi-ecosystem updates
require "dependabot/pull_request_creator/message_components"

title_component = Dependabot::PullRequestCreator::MessageComponents.create_title(
  type: :multi_ecosystem,
  dependencies: all_dependencies_from_multiple_ecosystems,
  source: source,
  credentials: credentials,
  dependency_group: dependency_group
)

pr_title = title_component.build
# => "Bump the \"all-deps\" group with 15 updates across multiple ecosystems"
```

### Using the Factory Pattern

For discoverability and ease of use:

```ruby
# Create single update title
title = MessageComponents.create_title(
  type: :single,
  dependencies: [dependency],
  source: source,
  credentials: credentials,
  files: files
)

# Create group update title
title = MessageComponents.create_title(
  type: :group,
  dependencies: [dep1, dep2, dep3],
  source: source,
  credentials: credentials,
  files: files,
  dependency_group: group
)

# Create multi-ecosystem title (for API)
title = MessageComponents.create_title(
  type: :multi_ecosystem,
  dependencies: all_deps,
  source: source,
  credentials: credentials,
  dependency_group: group
)

puts title.build  # => Formatted PR title
```

## Design Principles

1. **Core/API Consistency**: Same title formatting rules apply everywhere
2. **Single Source of Truth**: All PR title generation flows through these components
3. **Reusability**: API can import and use components without duplication
4. **Composable**: Complex components reuse simpler ones (e.g., `GroupUpdateTitle` uses `SingleUpdateTitle`)
5. **Testable**: Each component can be tested independently
6. **Type Safety**: Full Sorbet typing throughout
7. **Backward Compatibility**: `MessageBuilder` API remains unchanged

## Key Benefits for dependabot-api

Before this refactoring, dependabot-api had to:
- ❌ Duplicate PR title construction logic
- ❌ Duplicate prefix/capitalization logic  
- ❌ Manually stay in sync with core changes

After this refactoring, dependabot-api can:
- ✅ Import `MessageComponents` directly
- ✅ Use `MultiEcosystemTitle` component
- ✅ Get consistent formatting automatically
- ✅ Benefit from core improvements automatically

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
