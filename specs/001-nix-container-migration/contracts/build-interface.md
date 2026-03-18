# Contracts: Nix Build System CLI Interface

**Feature**: 001-nix-container-migration
**Date**: 2026-03-18

The Nix build system exposes its functionality through `nix build` and `nix run` commands.
These are the contracts that CI workflows, build scripts, and contributors interact with.

---

## 1. Flake Outputs (build targets)

All images are accessible as flake outputs under `packages.{system}.*`.

### Core image

```bash
# Build core image
nix build .#packages.x86_64-linux.core
nix build .#packages.aarch64-linux.core

# Load into Docker daemon
nix run .#packages.x86_64-linux.core.copyToDockerDaemon

# Push to GHCR
nix run .#packages.x86_64-linux.core.copyTo -- \
  docker://ghcr.io/dependabot/dependabot-updater-core:latest
```

### Ecosystem images

```bash
# Build a specific ecosystem
nix build .#packages.x86_64-linux.ecosystems.go_modules
nix build .#packages.x86_64-linux.ecosystems.npm_and_yarn
nix build .#packages.x86_64-linux.ecosystems.python

# Load into Docker daemon
nix run .#packages.x86_64-linux.ecosystems.go_modules.copyToDockerDaemon

# Push to GHCR (tag uses ecosystem mapping from script/_common)
nix run .#packages.x86_64-linux.ecosystems.go_modules.copyTo -- \
  docker://ghcr.io/dependabot/dependabot-updater-gomod:latest
```

### Development images

```bash
# Build dev image for a specific ecosystem
nix build .#packages.x86_64-linux.dev.go_modules

# Load into Docker daemon (used by bin/docker-dev-shell)
nix run .#packages.x86_64-linux.dev.go_modules.copyToDockerDaemon
```

---

## 2. Image naming contract

The Nix build MUST produce images with names matching the existing convention:

| Image | Docker name | GHCR path |
|-------|------------|-----------|
| Core | `dependabot-updater-core` | `ghcr.io/dependabot/dependabot-updater-core` |
| Ecosystem | `dependabot-updater-{tag}` | `ghcr.io/dependabot/dependabot-updater-{tag}` |

Where `{tag}` follows the ecosystem-to-tag mapping in `script/_common`:

| Ecosystem dir | Tag |
|--------------|-----|
| `docker_compose` | `docker-compose` |
| `dotnet_sdk` | `dotnet-sdk` |
| `go_modules` | `gomod` |
| `hex` | `mix` |
| `npm_and_yarn` | `npm` |
| `pre_commit` | `pre-commit` |
| `python` | `pip` |
| `git_submodules` | `gitsubmodule` |
| `github_actions` | `github-actions` |
| `rust_toolchain` | `rust-toolchain` |
| All others | Same as ecosystem dir name |

---

## 3. Environment variable contract

Every image MUST set these environment variables (verified by smoke tests):

### Core image

| Variable | Value |
|----------|-------|
| `DEPENDABOT` | `true` |
| `DEPENDABOT_HOME` | `/home/dependabot` |
| `DEPENDABOT_NATIVE_HELPERS_PATH` | `/opt` |
| `GIT_LFS_SKIP_SMUDGE` | `1` |
| `LC_ALL` | `en_US.UTF-8` |
| `LANG` | `en_US.UTF-8` |
| `PATH` | Must include `$DEPENDABOT_HOME/bin` |

### Ecosystem-specific (additive)

| Ecosystem | Variable | Value |
|-----------|----------|-------|
| npm_and_yarn | `NODE_EXTRA_CA_CERTS` | `/etc/ssl/certs/ca-certificates.crt` |
| npm_and_yarn | `NPM_CONFIG_AUDIT` | `false` |
| npm_and_yarn | `NPM_CONFIG_FUND` | `false` |
| python | `REQUESTS_CA_BUNDLE` | `/etc/ssl/certs/ca-certificates.crt` |
| python | `SSL_CERT_FILE` | `/etc/ssl/certs/ca-certificates.crt` |
| python | `PYENV_ROOT` | `/usr/local/.pyenv` |
| cargo | `RUSTUP_HOME` | `/opt/rust` |
| cargo | `CARGO_HOME` | `/opt/rust` |
| cargo | `CARGO_REGISTRIES_CRATES_IO_PROTOCOL` | `sparse` |
| maven | `MAVEN_HOME` | `/usr/share/maven` |
| go_modules | `PATH` | Must include `/opt/go/bin` |
| swift | `PATH` | Must include `/opt/swift/usr/bin` |
| docker | `PATH` | Must include `/opt/bin` |

---

## 4. Filesystem contract

### User

| Property | Value |
|----------|-------|
| Username | `dependabot` |
| UID | `1000` |
| GID | `1000` |
| Home | `/home/dependabot` |
| Shell | `/bin/bash` |

### Key directories

| Path | Owned by | Purpose |
|------|----------|---------|
| `/home/dependabot` | `dependabot:dependabot` | Home directory |
| `/home/dependabot/dependabot-updater` | `dependabot:dependabot` | Updater service code |
| `/home/dependabot/bin` | `dependabot:dependabot` | User binaries (git-shim) |
| `/opt` | `dependabot:dependabot` | Native helpers and toolchains |
| `/etc/ssl/certs` | `dependabot:dependabot` (group writable) | CA certificates |

---

## 5. script/build contract

The `script/build` command MUST continue to accept an ecosystem name and produce a runnable image:

```bash
# Existing interface (preserved)
script/build go_modules

# Under the hood, this now calls:
# 1. nix build .#packages.x86_64-linux.ecosystems.go_modules
# 2. nix run .#packages.x86_64-linux.ecosystems.go_modules.copyToDockerDaemon
#    (tags: ghcr.io/dependabot/dependabot-updater-gomod)
```

The `SKIP_BUILD` environment variable MUST continue to be respected.

---

## 6. bin/docker-dev-shell contract

The dev shell script MUST continue to accept an ecosystem name and start an interactive container:

```bash
bin/docker-dev-shell go_modules
# => running docker development shell
# [dependabot-core-dev] ~ $
```

The `--rebuild` flag MUST trigger a fresh `nix build` + load into Docker daemon.

Volume mounts for source code access MUST continue to work as before.
