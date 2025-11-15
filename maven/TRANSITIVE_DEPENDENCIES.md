# Maven Transitive Dependency Updates

This feature enhances the Maven updater to update dependent packages when updating a dependency version, preventing broken builds that can occur when dependencies have compatibility issues with updated transitive dependencies.

## Overview

When updating a Maven dependency, other dependencies in the project might depend on the specific version being updated. If these dependent packages are not also updated to compatible versions, the build can break. The TransitiveDependencyUpdater addresses this by:

1. Analyzing the Maven dependency tree to identify dependencies that depend on the target dependency
2. Finding compatible newer versions of these dependent dependencies
3. Updating both the target dependency and its dependents in a single operation

## Implementation

### Core Components

- **TransitiveDependencyUpdater**: Main class that handles the analysis and update logic
- **UpdateChecker Integration**: Detects when transitive updates are needed and coordinates the process
- **Maven Dependency Tree Analysis**: Uses Maven's native dependency tree to understand relationships

### Key Features

- **Conservative Approach**: Only updates dependencies for commonly used libraries to avoid unnecessary changes
- **Compatibility Checking**: Only updates to newer versions when they're likely to be compatible
- **Conflict Prevention**: Avoids conflicts with property-based multi-dependency updates
- **Experiment Flag**: Requires `maven_transitive_dependencies` experiment to be enabled

### Heuristics

The updater uses several heuristics to determine when to perform transitive updates:

1. **Common Libraries**: Focuses on commonly used libraries like Guava, Apache Commons, Jackson, etc.
2. **Version Analysis**: Only updates when newer compatible versions are available
3. **Property Conflicts**: Disabled when property-based versioning is in use

## Usage

The feature is automatically enabled when:

1. The `maven_transitive_dependencies` experiment flag is enabled
2. The dependency being updated is not using property-based versioning
3. The dependency is identified as commonly used in transitive relationships
4. Compatible newer versions are available for dependent packages

## Example

When updating `com.google.guava:guava` from `23.6-jre` to `23.7-jre`, the updater will:

1. Identify other dependencies that might depend on Guava
2. Check if newer versions of those dependencies are available
3. Update both Guava and its dependents to maintain compatibility

## Configuration

Enable the feature by setting the experiment flag:

```ruby
Dependabot::Experiments.enabled?(:maven_transitive_dependencies) # => true
```

## Testing

The feature includes comprehensive test coverage:

- Unit tests for TransitiveDependencyUpdater
- Integration tests with UpdateChecker
- Test coverage for various dependency scenarios

## Safety Features

- **Fallback Behavior**: Safe fallback when transitive analysis fails
- **Conservative Updates**: Only updates when confident about compatibility
- **Conflict Avoidance**: Prevents conflicts with existing update mechanisms
- **Logging**: Comprehensive logging for debugging and monitoring

## Limitations

- Requires Maven dependency tree analysis, which may not work in all project structures
- Currently focuses on commonly used libraries; less common dependencies are not updated
- Compatibility checking is heuristic-based rather than exhaustive
- Requires the experiment flag to be enabled