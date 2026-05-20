---
applyTo:
  - "**/*_spec.rb"
  - "**/spec/**"
  - "**/spec_helper.rb"
---

# Testing Guidelines

## Docker-Based Testing

All tests must run inside Docker containers. The development environment, dependencies, and native helpers are containerized and will not work on the host system. Never attempt to run tests directly on your machine.

## Quick Testing with `bin/test`

The `bin/test` script is the fastest way to run tests. It handles container setup automatically.

```bash
# Run a specific spec file
bin/test {ecosystem} spec/dependabot/{ecosystem}/file_updater_spec.rb

# Run the full ecosystem test suite
bin/test {ecosystem}

# Test common/ changes (uses the bundler container internally)
bin/test common spec/dependabot/file_fetchers/base_spec.rb

# Test updater/ changes (note: use --workdir updater, it maps to dependabot-updater in the container)
bin/test --workdir updater {ecosystem} rspec spec/path/to/spec.rb
```

The first run builds the Docker image and can take several minutes. Subsequent runs reuse the cached image and are much faster.

## Interactive Development with `bin/docker-dev-shell`

For iterative development where you need to run multiple commands, use the interactive shell:

```bash
# Start an interactive container shell
bin/docker-dev-shell {ecosystem}

# Inside the container:
cd {ecosystem} && rspec spec

# For updater tests (the folder is renamed inside containers):
cd dependabot-updater && rspec spec
```

## GitHub Actions / CI (Non-Interactive)

In CI environments where interactive shells are unavailable, use the non-interactive pattern:

```bash
# Build the ecosystem image
script/build {ecosystem}

# Run tests inside the container
docker run --rm --env "CI=true" ghcr.io/dependabot/dependabot-updater-{ecosystem} bash -c \
  "cd /home/dependabot/{ecosystem} && rspec spec"
```

## Testing `updater/` and `common/` Changes

The `updater/` directory is renamed to `dependabot-updater/` inside containers. Always use the container path when running updater tests.

```bash
# Test updater changes
bin/test --workdir updater {ecosystem} rspec spec/path/to/spec.rb

# Test common changes (runs inside the bundler container)
bin/test common spec/path/to/spec.rb
```

## Test Coverage Requirements

- All changes must be covered by tests to prevent regressions.
- Add tests for new functionality **before** implementing the feature.
- When fixing bugs, add a test that reproduces the issue **first**.
- All existing tests must continue to pass after your changes.

### Rules for Test Design

- **NEVER** test private methods directly — tests should only exercise public interfaces.
- **NEVER** modify production code visibility to accommodate tests. If a test needs access to a private method, the test design is wrong.
- **NEVER** add public methods solely for testing — this pollutes the production API.
- Tests should verify behavior through public APIs and production code paths (e.g., `fetch_files`), not isolated helper methods.

## Fixture-Based Testing

Use real dependency files as fixtures. Helper methods in `spec_helper.rb` generate realistic test data:

```ruby
let(:dependency_files) { bundler_project_dependency_files("example_project") }
```

Fixtures live in `{ecosystem}/spec/fixtures/`.

## Mocking External Calls

- Mock HTTP requests to package registries using **VCR** or **WebMock**.
- Use realistic registry responses to catch edge cases.
- Never make real network calls in tests.
