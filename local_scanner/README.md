# Dependabot Local Scanner

A local dependency scanner that allows developers to run Dependabot Core against local Ruby projects without requiring GitHub repository access.

## Quick Start

1. **Build the local scanner ecosystem:**
   ```bash
   # From the dependabot-core root directory
   script/build local_scanner
   ```

2. **Run a local scan on a project:**
   ```bash
   # From the dependabot-core root directory
   ./script/run_local_scanner /path/to/your/project
   ```

3. **Example usage:**
   ```bash
   ./script/run_local_scanner ~/development/my-ruby-project
   ```

## Usage

### Standard Method (Recommended)
```bash
# Build and run in one command
./script/run_local_scanner /path/to/project
```

### Development Container Method
```bash
# Start the development container for bundler ecosystem
./bin/docker-dev-shell bundler

# Inside the container, run tests
cd local_scanner
rspec spec
```

### Manual Build and Run
```bash
# Build the ecosystem image
script/build local_scanner

# Run manually with Docker
docker run --rm \
  -v "/path/to/project:/scan" \
  -v "$(pwd):/dependabot-core" \
  -w /dependabot-core \
  ghcr.io/dependabot/dependabot-updater-local_scanner:latest \
  bash -c "cd dependabot-updater && bundle install > /dev/null 2>&1 && cd ../local_scanner && ruby -I ../common/lib -I ../bundler/lib -I ../updater/lib bin/local_ruby_scan /scan"
```

## Features

- Local Ruby project dependency scanning
- Security vulnerability detection using Dependabot's Ruby Advisory Database
- Multiple output formats (summary, text, JSON)
- Docker container support with proper bundler helpers
- Integration with existing Dependabot infrastructure
- Fast execution with pre-built ecosystem image

## Testing

The local scanner follows the standard dependabot-core testing patterns:

- Uses the common spec helper infrastructure
- Integrates with existing RSpec setup
- Follows ecosystem-specific testing conventions
- Tests run via standard ecosystem approach

### Run Tests
```bash
# From dependabot-core root directory
script/build local_scanner
docker run --rm -v "$(pwd):/home/dependabot/dependabot-core" -w /home/dependabot/dependabot-core ghcr.io/dependabot/dependabot-updater-local_scanner:latest bash -c "cd dependabot-updater && bundle install > /dev/null 2>&1 && cd ../local_scanner && rspec spec --format progress"
```

## Architecture

The local scanner is implemented as a first-class ecosystem within dependabot-core:

- **Standard Ecosystem Structure**: Follows the same pattern as other ecosystems (bundler, cargo, etc.)
- **Integrated Build System**: Uses `script/build local_scanner` 
- **Proper Dependencies**: Includes bundler helpers and all required gems
- **Container Integration**: Works seamlessly with dependabot-core's Docker infrastructure

## Files

- **`bin/local_ruby_scan`**: Main scanning script (note: no .rb extension)
- **`Dockerfile`**: Standard ecosystem Dockerfile with bundler helpers
- **`lib/dependabot/local_scanner/`**: Core scanner implementation
- **`spec/`**: Comprehensive test suite

## What This Scanner Does

1. **Project Validation**: Ensures the target directory contains a valid Ruby project with Gemfile
2. **Dependency Parsing**: Uses Dependabot's FileParser to read Gemfile/Gemfile.lock
3. **Security Scanning**: Checks dependencies against Ruby Advisory Database for known vulnerabilities
4. **Output Generation**: Provides security-focused results in multiple formats

## Benefits

- 🚀 **Fast**: Pre-built ecosystem image with all dependencies
- 🔒 **Security-focused**: Default mode shows only security vulnerabilities
- 🐳 **Containerized**: Consistent environment across different machines
- 🔧 **Integrated**: Uses standard dependabot-core patterns and infrastructure
- 📊 **Reliable**: Leverages proven Dependabot classes and security databases
