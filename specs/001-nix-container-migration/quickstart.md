# Quickstart: Nix Container Migration

**Feature**: 001-nix-container-migration
**Date**: 2026-03-18

---

## Prerequisites

1. **Nix** with flakes enabled. Install via [Determinate Systems installer](https://install.determinate.systems/nix):

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh
   ```

2. **Docker** (for loading and running OCI images locally).

---

## Build the core image

```bash
cd dependabot-core
nix build .#packages.x86_64-linux.core
```

Load into Docker daemon:

```bash
nix run .#packages.x86_64-linux.core.copyToDockerDaemon
```

Verify:

```bash
docker run --rm ghcr.io/dependabot/dependabot-updater-core \
  bash -c "ruby --version && git --version && git lfs version"
```

---

## Build an ecosystem image

```bash
nix build .#packages.x86_64-linux.ecosystems.go_modules
nix run .#packages.x86_64-linux.ecosystems.go_modules.copyToDockerDaemon
```

Run tests:

```bash
docker run --rm ghcr.io/dependabot/dependabot-updater-gomod \
  bash -c "cd /home/dependabot/go_modules && rspec spec"
```

---

## Start a development shell

```bash
bin/docker-dev-shell go_modules
```

Inside the container:

```bash
cd go_modules && rspec spec
bin/dry-run.rb go_modules rsc/quote
```

---

## Bump a dependency version

To bump Go from 1.26.x to 1.27.x, edit `nix/ecosystems/go_modules.nix`:

```nix
# Change:
toolchainPackages = [ pkgs.go_1_26 ];
# To:
toolchainPackages = [ pkgs.go_1_27 ];
```

Then rebuild:

```bash
nix build .#packages.x86_64-linux.ecosystems.go_modules
```

---

## Bump all system packages

```bash
nix flake update nixpkgs
# Review changes in flake.lock
git diff nix/flake.lock
# Build and test
nix build .#packages.x86_64-linux.core
```

---

## Validate: smoke test all binaries

```bash
docker run --rm ghcr.io/dependabot/dependabot-updater-core bash -c '
  set -e
  ruby --version
  git --version
  git lfs version
  bzr --version
  hg --version
  gpg2 --version
  ssh -V
  gcc --version
  make --version
  locale -a | grep en_US.utf8
  echo "All smoke tests passed"
'
```
