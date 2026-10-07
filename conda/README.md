# `dependabot-conda`

Conda support for [`dependabot-core`][core-repo].

## Overview

Dependabot-Conda provides support for updating packages defined in Conda `environment.yml` files. It supports all package types from Conda channels, as well as PyPI packages installed via pip.

## Features

- Universal Conda Package Support: Updates packages from Conda channels regardless of language (Python, R, Julia, C/C++ libraries, system tools)
- Multi-Channel Support: Queries packages from anaconda, conda-forge, bioconda, and other public channels
- PyPI Integration: Supports pip packages via Python/PyPI integration
- Environment.yml Support: Parses and updates standard Conda environment files
- Dual-Source Routing: Automatically routes conda packages to Anaconda API and pip packages to PyPI
- Beta Feature: Protected by `enable-beta-ecosystems` flag

## How It Works

`dependabot-conda` uses dynamic routing based on where packages are defined:

- Conda packages (from `dependencies:` section) are queried via Anaconda channel APIs (api.anaconda.org)
- Pip packages (from `pip:` section) are queried via PyPI (delegated to Python ecosystem)

### Supported Package Types

Conda Packages (via Conda channels):

- Python packages
- R packages
- Julia packages
- System tools
- Any other conda-installable package

Pip Packages (via PyPI):

- Any Python package installable via `pip`

## Supported Environment Files

### Supported

Environments with simple version specifications:

```yaml
name: myenv
channels:
  - conda-forge
  - defaults
dependencies:
  - python=3.11
  - numpy>=1.24.0
  - r-base>=4.0
  - pip:
    - requests>=2.28.0
```

### Not Supported

Environments using fully-qualified package specifications (with build strings):

```yaml
dependencies:
  - python=3.11.0=h2628c8c_0_cpython  # Build string present
  - numpy=1.24.0=py311h1f0f07a_0      # Build string present
```

Fully-qualified specs pin to specific builds, making updates complex and potentially breaking. Use simple version specs for Dependabot compatibility.

## Scope Limitations

The following are out of scope for the current implementation:

- Security updates: Vulnerability-driven updates (planned for future release)
- Lock files: `conda-lock.yml` or similar lock file formats
- Private channels: Authentication to private Conda channels
- Fully-qualified specs: Packages pinned with build strings
- Environment inheritance: Environments that extend other environments

## Running locally

1. Start a development shell

   ```bash
   bin/docker-dev-shell conda
   ```

2. Run tests

   ```bash
   cd conda && rspec
   ```

3. Run dry-run against a repository

   ```bash
   bin/dry-run.rb conda owner/repo --enable-beta-ecosystems
   ```

### Configuration

To enable Conda support, add to your `.github/dependabot.yml`:

```yaml
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "conda"
    directory: "/"  # Location of environment.yml
    schedule:
      interval: "weekly"
```

[core-repo]: https://github.com/dependabot/dependabot-core
