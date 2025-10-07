# Contributing a New Ecosystem to Dependabot

This guide walks you through the process of adding support for a new package ecosystem to Dependabot. Contributing a new ecosystem is a significant undertaking that requires coordination with the Dependabot team.

## Prerequisites

Before you begin, research and decide on the following:

- **Ecosystem name**: What will be the canonical name of the ecosystem?
- **Package manager**: Does it have a package manager? What is its name?
- **Lockfiles**: Does it use lockfiles? What are the naming conventions for the lockfile(s) you plan to support?
- **Manifest files**: What are the manifest file names and formats?

## Getting Started

### Create an Issue First

**Before starting any implementation work**, check if there's already an [existing issue](https://github.com/dependabot/dependabot-core/issues) in the dependabot-core repository for the ecosystem you want to add. If there is an existing issue, you can use that issue to coordinate your contribution instead of creating a new one, since all interested users are likely already following the existing issue.

- The ecosystem you want to add
- Your implementation plan (including cooldown support)
- Timeline and milestones
- Any special requirements or challenges
- How your ecosystem handles release dates for cooldown functionality

This allows the Dependabot team to be in the loop with your plans and provide early feedback before you invest significant time in implementation.

## Overview

Adding a new ecosystem involves several phases:

1. **Core Implementation**: Implement the ecosystem logic in `dependabot-core`
2. **Advanced Features**: Implement cooldown functionality
3. **Beta Release**: Deploy as a beta feature for testing
4. **General Availability**: Remove beta restrictions after validation

## Phase 1: Core Implementation

### 1. Fork and Set Up dependabot-core

Fork the [dependabot-core](https://github.com/dependabot/dependabot-core) repository and create a new branch for your ecosystem.

### 2. Create the Ecosystem Structure

**Using the Scaffold Rake Task (Recommended)**

To quickly generate the boilerplate structure for your ecosystem, use the provided Rake task:

```bash
rake ecosystem:scaffold[your_ecosystem_name]
```

This will automatically create:
- Directory structure with all required folders
- Boilerplate for required classes (FileFetcher, FileParser, UpdateChecker, FileUpdater)
- Optional classes with deletion comments (MetadataFinder, Version, Requirement)
- Test files and fixtures directory
- Supporting configuration files (gemspec, README, .gitignore, etc.)

After scaffolding, you'll need to:
1. Implement the TODO sections in each generated file
2. Add comprehensive tests
3. Update supporting infrastructure (see section 5)

**Manual Setup**

Alternatively, you can create the structure manually. Create a new top-level ecosystem directory. Your ecosystem should be implemented as a standalone ecosystem rather than piggybacking off existing ones. You'll need to implement several key classes:

#### Required Classes

You must implement these four core classes for your ecosystem:

- FileFetcher (`file_fetcher.rb`): Handles fetching manifest and lockfiles from repositories, inherits from `Dependabot::FileFetchers::Base`
- FileParser (`file_parser.rb`): Parses manifest files to extract dependency information, inherits from `Dependabot::FileParsers::Base`
- UpdateChecker (`update_checker.rb`): Checks for available updates to dependencies, inherits from `Dependabot::UpdateCheckers::Base`
- FileUpdater (`file_updater.rb`): Updates manifest and lockfiles with new dependency versions, inherits from `Dependabot::FileUpdaters::Base`

#### Optional Classes

You may also implement these additional classes based on your ecosystem's needs:

- **MetadataFinder**: Finds metadata about packages (changelogs, release notes, etc.), inherits from `Dependabot::MetadataFinders::Base`
- **Requirements**: Updates version requirements in manifest files, inherits from `Dependabot::Requirement`
- **Version**: Handles version parsing and comparison logic, inherits from `Dependabot::Version`
- **Helper classes**: Any additional utilities your ecosystem requires

#### File Structure Example

```
new_ecosystem/lib/dependabot/
├── new_ecosystem.rb         # Main registration file
└── new_ecosystem/
    ├── file_fetcher.rb          # Required
    ├── file_parser.rb           # Required
    ├── update_checker.rb        # Required
    ├── file_updater.rb          # Required
    ├── metadata_finder.rb       # Optional
    ├── requirements_updater.rb  # Optional
    ├── version.rb              # Optional
    ├── requirement.rb          # Optional
    └── helpers/
        └── (any helper classes)
```

### 3. Register Your Ecosystem

**Main Registration File**

Create a main registration file at `new_ecosystem/lib/dependabot/new_ecosystem.rb` that requires all your classes and registers them with Dependabot. For an example, see the [Docker ecosystem registration file](https://github.com/dependabot/dependabot-core/blob/main/docker/lib/dependabot/docker.rb).

This file serves as the entry point for your ecosystem and ensures all classes are properly loaded and registered with Dependabot's internal lookup systems.

**Beta Feature Flag Implementation**

Implement beta feature flag: Hide file fetching behind the `allow_beta_ecosystems?` feature flag function to ensure your ecosystem only operates when beta ecosystems are enabled. This method will be available in your `FileFetcher` class since it inherits from `Dependabot::FileFetchers::Base`.

### 4. Add Comprehensive Unit Tests

Add comprehensive unit tests for all your classes as part of the core implementation:

```ruby
# Example test structure
spec/dependabot/your_ecosystem/
├── file_fetcher_spec.rb
├── file_parser_spec.rb
├── file_updater_spec.rb
├── update_checker_spec.rb
├── metadata_finder_spec.rb (if implemented)
└── fixtures/
    └── (test fixtures)
```

Ensure your tests cover:
- Happy path scenarios
- Edge cases and error conditions
- Different file formats and configurations
- Version parsing and comparison logic

### 5. Update Supporting Infrastructure

Your ecosystem implementation requires updates to numerous supporting files throughout the repository:

#### GitHub Workflows (`.github/workflows/`)
- Add your ecosystem to CI/CD workflows
  - [ci.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/workflows/ci.yml)
  - [ci-filters.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/ci-filters.yml)
  - [issue-labeler.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/issue-labeler.yml)
- Update test matrices to include your ecosystem
  - [smoke-filters.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/smoke-filters.yml)
  - [smoke-matrix.json](https://github.com/dependabot/dependabot-core/blob/main/.github/smoke-matrix.json)
- Add any ecosystem-specific build steps
  - [image-branch.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/workflows/image-branch.yml)
  - [image-latest.yml](https://github.com/dependabot/dependabot-core/blob/main/.github/workflows/image-latest.yml)

#### Development Scripts
- **Dry-run script**: Update the dry-run script to support your ecosystem for local testing
  - [docker-dev-shell](https://github.com/dependabot/dependabot-core/blob/main/bin/docker-dev-shell)
  - [dry-run.rb](https://github.com/dependabot/dependabot-core/blob/main/bin/dry-run.rb)
- **Development scripts**: Update any development convenience scripts
  - [script/dependabot](https://github.com/dependabot/dependabot-core/blob/main/script/dependabot)
#### Docker Configuration
- **docker-dev-shell**: Add your ecosystem to the development Docker environment
  - [Dockerfile.updater-core](https://github.com/dependabot/dependabot-core/blob/main/Dockerfile.updater-core)
- **Ecosystem Dockerfile**: Update Docker configurations if your ecosystem requires specific dependencies
  - [Example Helm Dockerfile](https://github.com/dependabot/dependabot-core/blob/main/helm/Dockerfile)

#### Dependency Management
- **Omnibus gem**: Add your ecosystem to the omnibus gem configuration
  - [updater/GemFile](https://github.com/dependabot/dependabot-core/blob/main/updater/Gemfile)
  - [updater/GemFile.lock](https://github.com/dependabot/dependabot-core/blob/main/updater/Gemfile.lock)
  - [dependabot-omnibus.gemspec](https://github.com/dependabot/dependabot-core/blob/main/omnibus/dependabot-omnibus.gemspec)
  - [omnibus.rb](https://github.com/dependabot/dependabot-core/blob/main/omnibus/lib/dependabot/omnibus.rb)
  - [Rakefile](https://github.com/dependabot/dependabot-core/blob/main/Rakefile)
- **Gemfile**: Update if your ecosystem introduces new Ruby dependencies
  - [GemFile](https://github.com/dependabot/dependabot-core/blob/main/Gemfile)
  - [GemFile.lock](https://github.com/dependabot/dependabot-core/blob/main/Gemfile.lock)
- **Package manifests**: Update any relevant package management files
  - [Example Helm Gemspec](https://github.com/dependabot/dependabot-core/blob/main/helm/dependabot-helm.gemspec)
  - [Example Helm Bundle Config](https://github.com/dependabot/dependabot-core/blob/main/helm/.bundle/config)

#### Documentation and Configuration
- **README updates**: Add your ecosystem to relevant documentation
  - [Example Helm README](https://github.com/dependabot/dependabot-core/blob/main/helm/README.md)
  - [Sorbet Config](https://github.com/dependabot/dependabot-core/blob/main/sorbet/config)
- **Configuration schemas**: Update any configuration validation schemas
  -  [setup.rb](https://github.com/dependabot/dependabot-core/blob/main/updater/lib/dependabot/setup.rb)


### 6. Implement Native Helpers (if needed)

Some ecosystems require native helpers for complex operations like dependency resolution. If your ecosystem needs this:

1. Create helper scripts in the appropriate language
2. Add Dockerfile configurations for building helper images
3. Implement Ruby wrappers to interact with the native helpers

## Phase 2: Advanced Features

### Cooldown Feature Implementation

As part of contributing a new ecosystem, you should also implement support for Dependabot's cooldown feature, which allows users to delay updates for a specified period after a new version is released.

#### What is Cooldown?

The cooldown feature addresses two major problems:

1. **Unstable updates causing system failures**: Some updates introduce critical bugs that are later fixed in subsequent versions
2. **Excessive update noise**: Frequent updates create update fatigue for development teams

#### Cooldown Configuration

Users can configure cooldowns in their `dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "your-ecosystem"
    directory: "/"
    schedule:
      interval: "daily"
    
    # Cooldown configuration
    cooldown:
      default-days: 5
      semver-major-days: 30
      semver-minor-days: 7
      semver-patch-days: 3
      include:
        - "package-name"
        - "package-pattern*"
      exclude:
        - "excluded-package"
```

#### Implementation Requirements

Your ecosystem implementation must support cooldown logic in the **UpdateChecker** class:

1. **Release Date Retrieval**: Your `UpdateChecker` must be able to determine when a version was released
2. **Cooldown Calculation**: Check if enough time has passed based on the configured cooldown period
3. **Version Selection**: When multiple versions exist within a cooldown period, select the appropriate version according to the cooldown rules

#### Key Considerations

- **Security Updates**: Consider whether security updates should bypass cooldown (this may depend on severity)
- **Version Selection Logic**: Determine which version to select when multiple versions are available after cooldown
- **Release Date Accuracy**: Ensure your implementation can accurately retrieve release timestamps from your ecosystem's registry

## Phase 3: Testing and Validation

### 1. Local Testing with Dry-Run

When adding a new ecosystem, you should validate your implementation locally before opening a PR. Dependabot provides a `bin/dry-run.rb` script that allows you to simulate update checks against real repositories.

The dry-run script can be run in your `bin/docker-dev-shell your-new-ecosystem-name [--rebuild]`

#### Running a Basic Dry-Run

Create (or fork) a public repository with representative manifest and lockfiles for your ecosystem. Then run:

```bash
# Run all updates
bin/dry-run.rb your-ecosystem your-github-user/your-sample-repo --enable-beta-ecosystems
```

You can also simulate security advisories by setting the `SECURITY_ADVISORIES` environment variable and use the `--security-updates-only` flag:

```bash
# Security updates only
SECURITY_ADVISORIES='[{"dependency-name":"numpy","patched-versions":["1.28.0"],"unaffected-versions":[],"affected-versions":["< 1.27.0"]}]'

bin/dry-run.rb your-ecosystem your-github-user/your-sample-repo --enable-beta-ecosystems --security-updates-only
```

#### Testing with Subdirectories

You can structure your test repo with subfolders containing different manifest scenarios and run targeted dry-runs using `--dir`:

```bash
REPO="your-org/your-sample-repo"
BASE_CMD="bin/dry-run.rb your-ecosystem $REPO --enable-beta-ecosystems"

$BASE_CMD --dir="/special-cases/private-repository"
$BASE_CMD --dir="/tier1-full-support/project-a"
```

This allows you to easily validate edge cases and multiple manifest types.

#### Automating Dry-Run Scenarios

For convenience, you can wrap your dry-run tests in a shell script inside the `dependabot-core-dev` shell:

```bash
#!/bin/bash
REPO="your-org/your-sample-repo"
BASE_CMD="bin/dry-run.rb your-ecosystem $REPO --enable-beta-ecosystems"

echo "Running Tier 1 tests..."
$BASE_CMD --dir="/tier1/project-one"
$BASE_CMD --dir="/tier1/project-two"

echo "Running Special Cases..."
$BASE_CMD --dir="/special-cases/custom-lockfiles"
```

#### Avoiding GitHub API Rate Limits

By default, the dry-run script runs without authentication and may hit GitHub API rate limits. To avoid this, set a personal access token:

```bash
export LOCAL_GITHUB_ACCESS_TOKEN=ghp_yourtokenhere
```

This will be automatically picked up by the dry-run script and give you higher rate limits.

### 2. Smoke Tests

Add smoke tests to the [dependabot/smoke-tests](https://github.com/dependabot/smoke-tests) repository. See the repository documentation for detailed instructions on creating and running smoke tests for your ecosystem.

## Phase 4: Coordination with Dependabot Team

Since ecosystem support requires changes to Dependabot's API and deployment infrastructure, you'll need to coordinate with the Dependabot team:

### 1. API Integration

The Dependabot team will need to:

- Add your ecosystem to Dependabot's API
- Update the configuration parsing logic
- Add feature flags for beta testing

### 2. Deployment Pipeline

Your ecosystem needs to be added to:

- Docker image builds
- Deployment configurations
- Monitoring and alerting

## Phase 5: Beta Testing

### 1. Feature Flag

Your ecosystem will be released behind a feature flag that the Dependabot team will configure. As part of your implementation, you must ensure that file fetching is properly hidden behind the `allow_beta_ecosystems?` feature flag function so your ecosystem only operates when beta ecosystems are enabled.

Initially, your ecosystem will be marked as beta. Users will need to:

```yaml
# .github/dependabot.yml
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "your-ecosystem"
    directory: "/"
    schedule:
      interval: "daily"
    # Test cooldown functionality during beta
    cooldown:
      default-days: 3
      semver-major-days: 7
```

### 2. Test Repository

Create a test repository with:

- Representative manifest files
- Various dependency scenarios
- Edge cases and complex configurations
- **Cooldown test scenarios** with different time periods and dependency types

### 3. Community Testing

Engage with the community to test your ecosystem:

- Share in relevant forums and communities
- Gather feedback on functionality and reliability
- Fix issues discovered during beta testing

## Phase 6: General Availability

After successful beta testing:

1. **Remove Beta Restrictions**: The ecosystem moves from beta to generally available
2. **Documentation**: Work with the team to update official documentation
3. **Announcement**: Coordinate announcement of the new ecosystem support with the Dependabot Team via your issue

## Best Practices

### Code Quality

- Follow existing code patterns and conventions
- Write comprehensive tests with good coverage
- Handle edge cases and error conditions gracefully
- Add clear documentation and comments where needed

### Reliability

- Implement proper error handling
- Add logging for debugging
- Test with various repository configurations
- Consider security implications
- **Achieve 95% initial success rate**: Your ecosystem implementation must demonstrate a 95% success rate during initial testing and validation

### Compatibility

- Support multiple versions of your ecosystem's tools
- Handle backward compatibility considerations
- Test with different operating systems if relevant

## Getting Help

- **Issues**: Use GitHub issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and community support
- **Documentation**: Refer to existing ecosystem implementations as examples

## Example Implementation

For a complete example, review the [Helm ecosystem implementation](https://github.com/dependabot/dependabot-core/pull/11726) which demonstrates:

- File fetching and parsing logic
- Version handling and comparison
- Update checking and file updating
- Comprehensive test coverage
- Integration with existing Dependabot patterns

## Timeline Expectations

Adding a new ecosystem timeline varies depending on the contributor and ecosystem complexity:

- **Core Implementation**: Timeline depends on contributor availability and ecosystem complexity
- **Testing**: 2-3 weeks for comprehensive testing including cooldown scenarios
- **Beta Period**: 4-8 weeks for community validation
- **General Availability**: 2-4 weeks for final polish and documentation

The timeline can vary significantly based on ecosystem complexity, cooldown implementation requirements, and the need for native helpers or special infrastructure.

---

Contributing a new ecosystem to Dependabot is a significant contribution to the open source community. Thank you for considering this contribution, and we look forward to working with you to expand Dependabot's ecosystem support!
