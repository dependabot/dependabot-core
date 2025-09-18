# Coverage Reporting with octocov

This project now uses [octocov](https://github.com/k1LoW/octocov) to aggregate SimpleCov coverage reports from all package manager ecosystems into a unified coverage report.

## How it works

1. **Test execution**: Each ecosystem's tests run in their respective Docker containers and generate SimpleCov coverage reports (`coverage/.resultset.json`)

2. **Coverage extraction**: Coverage files are extracted from containers using simple volume mounts

3. **Coverage aggregation**: After all tests complete, the `coverage` job:
   - Downloads coverage artifacts from all test jobs
   - Uses simple reorganization (no complex ecosystem mapping needed)
   - Runs octocov which auto-discovers all SimpleCov files

4. **Reporting**: octocov generates:
   - Pull request comments with coverage changes and diffs
   - GitHub Actions job summaries with coverage metrics
   - Coverage badges for the README
   - Historical coverage tracking via GitHub artifacts

## Configuration

The octocov configuration is in `.octocov.yml` and includes:

- **Auto-discovery**: Automatically finds SimpleCov `.resultset.json` files in any `coverage/` directory
- **Quality thresholds**: 70% minimum coverage, fails CI if not met
- **Code-to-test ratio**: Tracks test coverage quality (1:1.1 ratio target)
- **Badge generation**: Auto-generated coverage and ratio badges
- **PR integration**: Automatic coverage comments on pull requests

## Key Features

- **Zero maintenance**: No need to manually list ecosystem paths - octocov auto-discovers coverage files
- **Future-proof**: New ecosystems are automatically included without configuration changes
- **Robust**: Missing coverage files are gracefully ignored

## Coverage badges

The README now includes coverage badges that are automatically updated:

- ![Coverage](docs/coverage.svg) - Overall code coverage percentage
- ![Code to Test Ratio](docs/ratio.svg) - Ratio of test code to production code

## Benefits

- **Unified view**: Single coverage report across all 25+ package manager ecosystems
- **Quality gates**: Automatic CI failures if coverage drops below threshold
- **Developer feedback**: Immediate coverage feedback on pull requests
- **Historical tracking**: Coverage trends over time
- **Zero maintenance**: Works with existing SimpleCov setup, no changes needed
- **Simplified CI**: Minimal workflow complexity with auto-discovery
- **Future-proof**: New ecosystems automatically included without CI changes

## Files

- `.octocov.yml` - Main configuration file
- `.github/workflows/ci.yml` - Updated to include coverage aggregation job
- `docs/` - Directory for generated coverage badges
- `README.md` - Updated to display coverage badges
