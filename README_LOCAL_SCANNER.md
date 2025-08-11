# Local Dependabot Scanner

A simple, fast local dependency scanner that uses Dependabot's core classes directly to scan Ruby projects for security vulnerabilities and updates.

## Quick Start

1. **Build the custom scanner image:**
   ```bash
   ./script/build_custom_image.sh
   ```

2. **Run a security scan (default behavior):**
   ```bash
   docker run --rm -v "$(pwd):/repo" dependabot-scanner-local:latest \
     ruby bin/local_ruby_scan.rb /repo
   ```

3. **Scan a different project:**
   ```bash
   docker run --rm -v "/path/to/your/project:/repo" dependabot-scanner-local:latest \
     ruby bin/local_ruby_scan.rb /repo
   ```

## Default Behavior

The scanner runs in **security-only mode** with **summary output** by default:
- 🔒 Only shows dependencies with available updates (potential security fixes)
- 📊 Provides concise summary output
- 🚨 Focuses on what needs attention

## Command Line Options

### Scan Modes
- **`--security-only`** (default): Only show dependencies with security vulnerabilities
- **`--security-details`**: Show security vulnerabilities with detailed information  
- **`--all-updates`**: Show all available updates (not just security)

### Output Options
- **`--output-format FORMAT`**: Choose output format
  - `summary` (default): Concise summary with counts and names
  - `text`: Full detailed output
  - `json`: Machine-readable JSON output
- **`--show-details`**: Show detailed update information

### Examples

**Default security scan (summary output):**
```bash
ruby bin/local_ruby_scan.rb /path/to/project
```

**All updates with detailed output:**
```bash
ruby bin/local_ruby_scan.rb --all-updates --show-details /path/to/project
```

**Security scan with JSON output:**
```bash
ruby bin/local_ruby_scan.rb --output-format json /path/to/project
```

**Security details with full text output:**
```bash
ruby bin/local_ruby_scan.rb --security-details --output-format text /path/to/project
```

## Architecture

The scanner maintains complete separation between environments:

- **Scanner Environment**: Pre-installed Ruby gems and Dependabot classes
- **Project Environment**: Your project's dependencies (never touched by scanner)

This ensures:
- ✅ Fast startup (no dependency installation)
- ✅ Reliable scanning (consistent scanner environment)
- ✅ No interference with your project's dependencies
- ✅ Reproducible results

## Files

- **`local_ruby_scan.rb`**: Main scanning script with multiple modes and output formats
- **`Dockerfile.local`**: Custom Docker image with pre-installed dependencies
- **`build_custom_image.sh`**: Script to build the custom scanner image

## How It Works

1. **Environment Setup**: Dockerfile pre-installs all required gems
2. **Project Mounting**: Your project is mounted as a volume
3. **Dependency Parsing**: Uses Dependabot's `FileParser` to read Gemfile/Gemfile.lock
4. **Update Checking**: Uses Dependabot's `UpdateChecker` to find available updates
5. **Output Formatting**: Provides summary, text, or JSON output based on your preferences

## Benefits

- 🚀 **Fast**: No dependency installation on each run
- 🔒 **Security-focused**: Default mode shows only what needs attention
- 📊 **Flexible**: Multiple output formats for different use cases
- 🐳 **Containerized**: Consistent environment across different machines
- 🎯 **Focused**: Security-only mode by default, with options for more detail

## Development

To modify the scanner:

1. Edit `local_scan.rb`
2. Edit `Dockerfile.local` if adding new dependencies
3. Run `./build_custom_image.sh` to rebuild
4. Test with your project

The scanner is designed to be easily extensible for additional scanning modes and output formats.
