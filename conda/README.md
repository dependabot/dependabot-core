# `dependabot-conda`

Conda support for [`dependabot-core`][core-repo].

## Overview

Dependabot-Conda provides support for updating Python packages defined in Conda `environment.yml` files. This implementation focuses on Python packages only, supporting both conda channel packages (main dependencies section) and PyPI packages (pip section).

## Features

- **Python Package Updates**: Manages Python packages from both conda channels and PyPI
- **Environment.yml Support**: Parses and updates standard Conda environment files
- **Dual Source Support**: Handles packages from conda channels (defaults, conda-forge) and pip (PyPI)
- **Security Updates**: Leverages existing Python/PyPI advisory database for vulnerability detection
- **Beta Feature**: Protected by feature flag for safe rollout

## Supported Environment Types

**Tier 1: Full Support** - Environments with simplified conda specifications

- Main dependencies using simplified syntax: `package=1.2.3`, `package>=1.2.0`  
- Optional pip section with any packages
- All Python packages from both sections are managed

**Tier 2: Pip-Only Support** - Environments with fully qualified conda packages + pip section

- Main dependencies using fully qualified syntax: `package=1.2.3=py313hd6b623d_100`
- Must have pip section with packages
- Only pip section packages are managed

**Tier 3: No Support** - Pure fully qualified environments

- All dependencies use fully qualified syntax
- No pip section present
- Environment is rejected with clear error message

### Scope Limitations

This implementation focuses on Python packages only. The following are explicitly out of scope for Phase 1:

- Non-Python packages (R packages, system tools, etc.)
- Lock file support (conda-lock.yml)
- Custom conda channels beyond defaults/conda-forge
- Complex environment inheritance
- Cross-language dependency management

## Running locally

1. Start a development shell

   ```bash
   bin/docker-dev-shell conda
   ```

2. Run tests

   ```bash
   cd conda && rspec
   ```

### Configuration

To enable Conda support, add to your `dependabot.yml`:

```yaml
version: 2
enable-beta-ecosystems: true
updates:
  - package-ecosystem: "conda"
    directory: "/"
    schedule:
      interval: "weekly"
```

[core-repo]: https://github.com/dependabot/dependabot-core
