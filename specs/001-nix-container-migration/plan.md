# Implementation Plan: Nix Container Migration

**Branch**: `001-nix-container-migration` | **Date**: 2026-03-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-nix-container-migration/spec.md`

## Summary

Replace the Ubuntu 24.04 + Dockerfile-based container build pipeline with Nix + nix2container. The core image (`Dockerfile.updater-core`), all 30+ ecosystem images, and the development image (`Dockerfile.development`) will be defined as Nix expressions that produce OCI-compatible images. This centralizes toolchain version management, makes builds reproducible, and eliminates the need to manually install or PPA-pin packages from Ubuntu.

## Technical Context

**Language/Version**: Nix (flakes, nix2container library); Ruby 3.4.x (existing runtime); Bash (build scripts)
**Primary Dependencies**: nix2container (OCI image builder), nixpkgs (package set, pinned revision), Nix flakes
**Storage**: N/A (build system, no persistent storage)
**Testing**: RSpec (existing ecosystem test suites), shell-based smoke tests for binary presence/version checks
**Target Platform**: Linux containers (OCI images), amd64 and arm64
**Project Type**: Build system / infrastructure
**Performance Goals**: Image rebuild for a single-dependency version bump ≤ current Dockerfile rebuild time; full parallel build of all ecosystems via `nix build`
**Constraints**: Must maintain backward compatibility with `bin/docker-dev-shell`, `bin/dry-run.rb`, CI workflows; transition period where Dockerfiles and Nix coexist
**Scale/Scope**: 35 Dockerfiles (1,577 total lines), 30+ ecosystem images, ~20 distinct external toolchains

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Plugin Architecture | **PASS** | Layered image structure (core → ecosystem → dev) preserved. Each ecosystem gets its own Nix expression, paralleling the current per-ecosystem Dockerfile. `rake ecosystem:create` updated to scaffold Nix definitions. |
| II | Container-Isolated Execution | **PASS** | All execution still happens inside OCI containers. The layered hierarchy is maintained; only the build tool changes from `docker build` to `nix build`. Constitution amended (v1.0.1) to say "OCI containers" instead of "Docker containers". Native helpers still rebuilt inside containers. |
| III | Security-First Design | **PASS** | Credential proxy pattern is orthogonal to image build system. Nix images do not embed credentials. The `dependabot` user and permission model are preserved. |
| IV | Test-Accompanied Changes | **PASS** | Existing RSpec suites serve as the acceptance gate — 100% pass rate on Nix images required. Smoke tests added for binary presence/version. |
| V | Upstream Alignment | **PASS** | Nix pinning model makes version bumps a single-line change and simplifies staying current with upstream releases. |
| — | Ecosystem Standards | **PASS** | Per-ecosystem directory structure unchanged. Native helpers remain in `{ecosystem}/helpers/`. |
| — | Development Workflow | **PASS** | `bin/docker-dev-shell` continues to work by pointing at Nix-built images. Volume mounts, dry-runs, and debug workflows preserved. |

**Gate result**: All principles pass. No violations to track.

## Project Structure

### Documentation (this feature)

```text
specs/001-nix-container-migration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
nix/
├── flake.nix                    # Top-level flake: inputs (nixpkgs, nix2container), outputs (all images)
├── flake.lock                   # Pinned dependency revisions
├── core.nix                     # Core image definition (replaces Dockerfile.updater-core)
├── development.nix              # Development overlay (replaces Dockerfile.development)
├── lib/
│   ├── mkEcosystemImage.nix     # Shared helper: build an ecosystem image layered on core
│   └── mkDevImage.nix           # Shared helper: add dev tools to any ecosystem image
├── packages/
│   └── git-shim.nix             # Fixed-output derivation for the git-shim binary
└── ecosystems/
    ├── go_modules.nix           # Per-ecosystem: Go runtime + native helpers
    ├── npm_and_yarn.nix         # Per-ecosystem: Node.js + npm + pnpm + yarn + corepack
    ├── python.nix               # Per-ecosystem: Multiple Python versions + pyenv shims
    ├── bundler.nix              # Per-ecosystem: Bundler helpers only (Ruby already in core)
    ├── cargo.nix                # Per-ecosystem: Rust toolchain
    ├── hex.nix                  # Per-ecosystem: Erlang + Elixir
    ├── maven.nix                # Per-ecosystem: JDK + Maven
    ├── swift.nix                # Per-ecosystem: Swift toolchain
    ├── ...                      # One .nix file per ecosystem (30+ total)
    └── silent.nix               # Minimal: just core + gem source copy

.github/workflows/
├── images-latest.yml            # Updated: `nix build` instead of `docker build`
├── images-updater-core.yml      # Updated: `nix build .#core` instead of `script/build common`
└── ci.yml                       # Updated: use Nix-built images for test runs

script/
├── build                        # Updated: call `nix build` instead of `docker build`
└── _common                      # Updated: image loading from Nix store tarball

bin/
└── docker-dev-shell             # Updated: reference Nix-built dev images

rakelib/
└── ecosystem.rake               # Updated: scaffold Nix expression for new ecosystems
```

**Structure Decision**: A top-level `nix/` directory houses all Nix expressions. Each ecosystem gets a single `.nix` file under `nix/ecosystems/`. Shared logic (layering, user creation, env vars) lives in `nix/lib/`. This parallels the current pattern where each ecosystem has its own `Dockerfile` but they all share the `Dockerfile.updater-core` base. The existing Dockerfiles remain in place during the transition period (FR-012) and are removed ecosystem-by-ecosystem once validated.

## Complexity Tracking

> No constitution violations — table intentionally left empty.
