# Tasks: Nix Container Migration

**Input**: Design documents from `/specs/001-nix-container-migration/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Not explicitly requested in spec. Smoke-test validation is embedded in implementation tasks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

- Nix expressions: `nix/` at repository root
- Build scripts: `script/` at repository root
- CI workflows: `.github/workflows/` at repository root
- Ecosystem sources: `{ecosystem}/` at repository root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Nix flake initialization and shared library creation

- [ ] T001 Create `nix/` directory structure per plan (`nix/`, `nix/lib/`, `nix/packages/`, `nix/ecosystems/`)
- [ ] T002 Initialize Nix flake with nixpkgs and nix2container inputs in `nix/flake.nix`
- [ ] T003 Pin nixpkgs unstable and nix2container revisions via `nix flake lock` generating `nix/flake.lock`
- [ ] T004 [P] Implement `mkUser` helper function in `nix/lib/mkUser.nix` (creates /etc/passwd, /etc/group, /etc/shadow for dependabot:1000:1000)
- [ ] T005 [P] Implement `fetchGitShim` fixed-output derivation in `nix/packages/git-shim.nix` (downloads git-shim tarball for amd64 and arm64)
- [ ] T006 [P] Implement `mkEcosystemImage` shared builder in `nix/lib/mkEcosystemImage.nix` (accepts name, fromImage, toolchainPackages, helperBuildScript, envVars, sourceGlob)
- [ ] T007 [P] Implement `mkDevImage` shared builder in `nix/lib/mkDevImage.nix` (overlays dev tools onto any ecosystem image)

**Checkpoint**: Nix scaffolding complete. Shared library ready for use by core and ecosystem image definitions.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core image must be buildable before any ecosystem image can layer on top of it

**⚠️ CRITICAL**: No user story work can begin until this phase is complete. The core image is the `fromImage` for every ecosystem.

- [ ] T008 Implement core image system layer in `nix/core.nix` (git, git-lfs, breezy, mercurial, gnupg, openssh, ca-certificates, gcc, make, gmp, zlib, unzip, zstd, file, libyaml, glibcLocales)
- [ ] T009 Implement core image Ruby layer in `nix/core.nix` (Ruby 3.4.x, RubyGems, Bundler via pkgs.ruby)
- [ ] T010 Implement core image git-shim layer in `nix/core.nix` (uses fetchGitShim from T005, places binary in ~/bin/)
- [ ] T011 Implement core image user setup in `nix/core.nix` (uses mkUser from T004, creates dependabot user with home directory)
- [ ] T012 Implement core image gem bundle layer in `nix/core.nix` (copies updater/Gemfile + Gemfile.lock, runs bundle install as Nix derivation)
- [ ] T013 Implement core image source layer in `nix/core.nix` (copies common/, omnibus/, ecosystem stubs, updater/ source code)
- [ ] T014 Implement core image environment variables in `nix/core.nix` (DEPENDABOT=true, DEPENDABOT_HOME, DEPENDABOT_NATIVE_HELPERS_PATH, GIT_LFS_SKIP_SMUDGE, LC_ALL, LANG, PATH per contracts/build-interface.md)
- [ ] T015 Implement core image OCI config in `nix/core.nix` (User=dependabot, WorkingDir=/home/dependabot/dependabot-updater, Cmd=bin/run)
- [ ] T016 Wire core image into flake outputs in `nix/flake.nix` (packages.x86_64-linux.core and packages.aarch64-linux.core)
- [ ] T017 Validate core image builds successfully via `nix build .#packages.x86_64-linux.core`
- [ ] T018 Validate core image loads into Docker via `nix run .#packages.x86_64-linux.core.copyToDockerDaemon` and smoke-test all binaries (ruby, git, git-lfs, bzr, hg, gpg2, ssh, gcc, make, locale)

**Checkpoint**: Core image fully functional. Ecosystem images can now layer on top of it.

---

## Phase 3: User Story 1 — Core Image Built with Nix (Priority: P1) 🎯 MVP

**Goal**: The Nix-built core image is validated as a drop-in replacement for the current `Dockerfile.updater-core` image. Existing ecosystem Dockerfiles can use it as their `FROM` base. Build scripts updated to support Nix path.

**Independent Test**: Build core image with Nix, load into Docker, run updater RSpec suite inside it, verify 100% pass rate. Verify an existing ecosystem Dockerfile builds against the Nix core image.

### Implementation for User Story 1

- [ ] T019 [US1] Update `script/_common` to add a `nix_build()` function alongside existing `docker_build()` in `script/_common`
- [ ] T020 [US1] Update `script/build` to detect Nix availability and call `nix_build()` when `USE_NIX=1` is set, falling back to `docker_build()` in `script/build`
- [ ] T021 [US1] Verify ecosystem Dockerfile backward compatibility by building `silent/Dockerfile` with `FROM` pointing at the Nix-built core image
- [ ] T022 [US1] Run the updater RSpec suite (`cd dependabot-updater && rspec spec`) inside the Nix-built core image and verify 100% pass rate
- [ ] T023 [US1] Verify environment variable contract by running `docker run --rm <core-image> env` and checking all variables from contracts/build-interface.md Section 3
- [ ] T024 [US1] Verify filesystem contract by running `docker run --rm <core-image> id dependabot` and checking UID/GID/home from contracts/build-interface.md Section 4
- [ ] T025 [US1] Verify tool versions are equal-or-newer than current Ubuntu image by comparing `docker run` output of version commands across both images

**Checkpoint**: Core image is a validated drop-in replacement. Build scripts support both Nix and Docker paths.

---

## Phase 4: User Story 2 — Ecosystem Images Built with Nix (Priority: P2)

**Goal**: All 30+ ecosystem images are defined as Nix expressions layered on the core image. Each ecosystem's RSpec suite passes inside its Nix-built image.

**Independent Test**: For each migrated ecosystem, build its Nix image, load into Docker, verify toolchain versions, run `rspec spec`.

### Pilot ecosystems (simple → complex)

- [ ] T026 [P] [US2] Implement silent ecosystem image in `nix/ecosystems/silent.nix` (minimal: core + gem source copy only)
- [ ] T027 [P] [US2] Implement docker ecosystem image in `nix/ecosystems/docker.nix` (core + cosign + regctl binaries at /opt/bin)
- [ ] T028 [P] [US2] Implement bundler ecosystem image in `nix/ecosystems/bundler.nix` (core + bundler helpers build via runCommand)
- [ ] T029 [US2] Implement go_modules ecosystem image in `nix/ecosystems/go_modules.nix` (core + pkgs.go_1_26 at /opt/go + native helpers build)
- [ ] T030 [US2] Implement npm_and_yarn ecosystem image in `nix/ecosystems/npm_and_yarn.nix` (core + pkgs.nodejs_24 + corepack + pnpm + yarn-berry + npm + native helpers build + ecosystem env vars)

### Pilot validation

- [ ] T031 [US2] Wire pilot ecosystem images into flake outputs in `nix/flake.nix` (packages.{system}.ecosystems.{silent,docker,bundler,go_modules,npm_and_yarn})
- [ ] T032 [US2] Validate silent ecosystem: build, load, run `rspec spec` inside container
- [ ] T033 [P] [US2] Validate docker ecosystem: build, load, verify `cosign` and `regctl` on PATH, run `rspec spec`
- [ ] T034 [P] [US2] Validate bundler ecosystem: build, load, verify helper binaries at /opt/bundler, run `rspec spec`
- [ ] T035 [US2] Validate go_modules ecosystem: build, load, verify `go version`, run `rspec spec`
- [ ] T036 [US2] Validate npm_and_yarn ecosystem: build, load, verify `node --version`, `npm --version`, `pnpm --version`, `yarn --version`, run `rspec spec`

### Complex ecosystems

- [ ] T037 [US2] Implement python ecosystem image in `nix/ecosystems/python.nix` (core + pkgs.python311 through pkgs.python314 + pyenv symlink shim at $PYENV_ROOT/versions/ + older nixpkgs pin for Python 3.9/3.10 + native helpers build per version)
- [ ] T038 [US2] Implement cargo ecosystem image in `nix/ecosystems/cargo.nix` (core + pkgs.rustc + pkgs.cargo at /opt/rust + cargo config for git CLI)
- [ ] T039 [US2] Implement hex ecosystem image in `nix/ecosystems/hex.nix` (core + pkgs.beam26Packages.erlang + pkgs.elixir + mix dependencies)
- [ ] T040 [US2] Implement maven ecosystem image in `nix/ecosystems/maven.nix` (core + pkgs.jdk21 + pkgs.maven at /usr/share/maven + mvn symlink)
- [ ] T041 [US2] Implement swift ecosystem image in `nix/ecosystems/swift.nix` (core + Swift 6.2.x via fixed-output derivation downloading official tarball at /opt/swift)
- [ ] T042 [P] [US2] Implement composer ecosystem image in `nix/ecosystems/composer.nix` (core + PHP + Composer)
- [ ] T043 [P] [US2] Implement pub ecosystem image in `nix/ecosystems/pub.nix` (core + pkgs.flutter/dart)
- [ ] T044 [P] [US2] Implement terraform ecosystem image in `nix/ecosystems/terraform.nix` (core + terraform binary)
- [ ] T045 [P] [US2] Implement opentofu ecosystem image in `nix/ecosystems/opentofu.nix` (core + opentofu binary)
- [ ] T046 [P] [US2] Implement gradle ecosystem image in `nix/ecosystems/gradle.nix` (core + pkgs.jdk21 + pkgs.gradle)
- [ ] T047 [P] [US2] Implement nuget ecosystem image in `nix/ecosystems/nuget.nix` (core + .NET SDK)

### Remaining ecosystems (minimal or single-binary)

- [ ] T048 [P] [US2] Implement bazel ecosystem image in `nix/ecosystems/bazel.nix`
- [ ] T049 [P] [US2] Implement bun ecosystem image in `nix/ecosystems/bun.nix` (core + bun runtime)
- [ ] T050 [P] [US2] Implement conda ecosystem image in `nix/ecosystems/conda.nix`
- [ ] T051 [P] [US2] Implement devcontainers ecosystem image in `nix/ecosystems/devcontainers.nix`
- [ ] T052 [P] [US2] Implement docker_compose ecosystem image in `nix/ecosystems/docker_compose.nix`
- [ ] T053 [P] [US2] Implement dotnet_sdk ecosystem image in `nix/ecosystems/dotnet_sdk.nix` (core + .NET SDK)
- [ ] T054 [P] [US2] Implement elm ecosystem image in `nix/ecosystems/elm.nix` (core + pkgs.elmPackages.elm)
- [ ] T055 [P] [US2] Implement git_submodules ecosystem image in `nix/ecosystems/git_submodules.nix`
- [ ] T056 [P] [US2] Implement github_actions ecosystem image in `nix/ecosystems/github_actions.nix`
- [ ] T057 [P] [US2] Implement helm ecosystem image in `nix/ecosystems/helm.nix` (core + pkgs.kubernetes-helm)
- [ ] T058 [P] [US2] Implement julia ecosystem image in `nix/ecosystems/julia.nix` (core + pkgs.julia)
- [ ] T059 [P] [US2] Implement pre_commit ecosystem image in `nix/ecosystems/pre_commit.nix` (core + depends on go_modules + bundler images)
- [ ] T060 [P] [US2] Implement rust_toolchain ecosystem image in `nix/ecosystems/rust_toolchain.nix`
- [ ] T061 [P] [US2] Implement uv ecosystem image in `nix/ecosystems/uv.nix` (core + Python versions + uv binary)
- [ ] T062 [P] [US2] Implement vcpkg ecosystem image in `nix/ecosystems/vcpkg.nix`

### Wire remaining ecosystems + batch validation

- [ ] T063 [US2] Wire all remaining ecosystem images into flake outputs in `nix/flake.nix`
- [ ] T064 [US2] Validate python ecosystem: build, load, verify all Python versions via pyenv (explicitly run `pyenv exec python3.11 --version`, `pyenv exec python3.12 --version`, etc. for each installed version), run `rspec spec`
- [ ] T065 [P] [US2] Validate cargo ecosystem: build, load, verify `rustc --version`, `cargo --version`, run `rspec spec`
- [ ] T066 [P] [US2] Validate hex ecosystem: build, load, verify `erl` + `elixir --version`, run `rspec spec`
- [ ] T067 [P] [US2] Validate maven ecosystem: build, load, verify `java --version`, `mvn --version`, run `rspec spec`
- [ ] T068 [P] [US2] Validate swift ecosystem: build, load, verify `swift --version`, run `rspec spec`
- [ ] T069 [US2] Batch-validate all remaining ecosystems by building each image and running its `rspec spec`

**Checkpoint**: All 30+ ecosystem images build from Nix and pass their RSpec suites.

---

## Phase 5: User Story 3 — Development Shell via Nix (Priority: P3)

**Goal**: Contributors can use `bin/docker-dev-shell` with Nix-built development images that include all debug/dev tools.

**Independent Test**: Run `bin/docker-dev-shell go_modules`, verify the prompt, run `rspec spec`, run `bin/dry-run.rb go_modules rsc/quote`.

### Implementation for User Story 3

- [ ] T070 [US3] Implement development image definition in `nix/development.nix` (overlays vim, strace, ltrace, gdb, shellcheck, libgit2, cmake, pkg-config + .vimrc + PS1 prompt + development gems)
- [ ] T071 [US3] Wire development image outputs into flake in `nix/flake.nix` (packages.{system}.dev.{ecosystem} for each ecosystem)
- [ ] T072 [US3] Update `bin/docker-dev-shell` to load Nix-built dev images when `USE_NIX=1` is set (call `nix run .#dev.{ecosystem}.copyToDockerDaemon`, then `docker run` as before)
- [ ] T073 [US3] Preserve `--rebuild` flag behavior in `bin/docker-dev-shell` to trigger fresh `nix build` + reload
- [ ] T074 [US3] Validate dev shell for go_modules: run `bin/docker-dev-shell go_modules`, verify prompt, run `rspec spec` and `bin/dry-run.rb go_modules rsc/quote` inside container
- [ ] T075 [P] [US3] Validate dev shell for npm_and_yarn: run `bin/docker-dev-shell npm_and_yarn`, verify tools, run `rspec spec`
- [ ] T076 [P] [US3] Validate dev shell for python: run `bin/docker-dev-shell python`, verify tools, run `rspec spec`
- [ ] T077 [US3] Verify volume mounts work: edit a Ruby file on host, confirm change visible inside running dev container

**Checkpoint**: Development workflow fully functional with Nix-built images.

---

## Phase 6: User Story 4 — CI/CD Pipeline Produces Nix Images (Priority: P4)

**Goal**: GitHub Actions workflows build, push, and sign container images via Nix instead of `docker build`.

**Independent Test**: Trigger CI, verify images published to GHCR for multiple ecosystems on both amd64 and arm64, pull and smoke-test.

### Implementation for User Story 4

- [ ] T078 [US4] Update `.github/workflows/images-updater-core.yml` to install Nix (DeterminateSystems/nix-installer-action), add magic-nix-cache, build core image via `nix build`, push via `nix run .#core.copyTo`, sign with cosign
- [ ] T079 [US4] Update `.github/workflows/images-latest.yml` to install Nix, add magic-nix-cache, replace `script/build` + `docker push` with `nix build .#ecosystems.{name}` + `nix run .#ecosystems.{name}.copyTo` for each ecosystem in the matrix
- [ ] T080 [US4] Add arm64 runner (`ubuntu-24.04-arm`) to the matrix in `.github/workflows/images-latest.yml` for multi-arch builds alongside x86_64
- [ ] T081 [US4] Update `.github/workflows/ci.yml` to build ecosystem images via Nix for test runs (replace `script/build` + `docker run` with Nix equivalents)
- [ ] T082 [US4] Implement Skopeo GHCR authentication in CI workflows (use `--dest-creds` with `github.actor` and `GITHUB_TOKEN`)
- [ ] T083 [US4] Verify cosign signing works with Nix-pushed images by inspecting the signed digest in GHCR after CI run
- [ ] T084 [US4] Verify selective caching: change one ecosystem Nix expression, trigger CI, confirm only that ecosystem rebuilds while others use cache

**Checkpoint**: CI/CD pipeline fully migrated to Nix-based builds.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup transition artifacts, update scaffolding, documentation

**⚠️ TRANSITION GATE**: Dockerfile removal (T088–T091) MUST NOT begin until: (a) all ecosystem RSpec suites pass on Nix-built images (T069), (b) CI has successfully built and published Nix images for at least 2 consecutive releases without regression (T084), and (c) dev shell is validated (T077). This gate ensures safe rollback is possible during the transition period (FR-012).

- [ ] T085 Update `rakelib/ecosystem.rake` to scaffold a `nix/ecosystems/{name}.nix` file when running `rake ecosystem:create[name]`
- [ ] T086 [P] Update `CONTRIBUTING.md` to document Nix prerequisites for development (install Nix, how to build/load images, macOS contributor workflow: document that macOS users must either set up a Linux builder VM for local Nix builds or pull pre-built images from GHCR)
- [ ] T087 [P] Update `README.md` Development Guide section to include Nix build instructions alongside existing Docker instructions
- [ ] T088 Remove `Dockerfile.updater-core` once core image is fully validated and CI uses Nix exclusively
- [ ] T089 Remove `Dockerfile.development` once dev shell is fully validated with Nix images
- [ ] T090 Remove per-ecosystem `Dockerfile` files from all 30+ ecosystem directories (batch removal after full validation)
- [ ] T091 Remove Docker-specific build functions from `script/_common` and `script/build` (once Nix is the sole build path)
- [ ] T092 Run quickstart.md validation end-to-end (build core, build ecosystem, start dev shell, bump a version, smoke test)
- [ ] T093 Verify SC-005: count total lines of Nix expressions vs. total lines of removed Dockerfiles (≤ 1,577 lines)
- [ ] T094 Verify SC-003: measure time from clean checkout to running dev shell using pre-built Nix images (must be ≤ 10 minutes)
- [ ] T095 Verify SC-004: measure rebuild time after a single ecosystem dependency version bump (must be ≤ current Dockerfile rebuild time)
- [ ] T096 Verify SC-006: run `nix build` targeting all ecosystem images in a single invocation, confirm all build with proper caching
- [ ] T097 Verify SC-007: demonstrate a single-line version bump (e.g., Go 1.26 → 1.27) and confirm no other files need changing
- [ ] T098 Verify SC-008: run `bin/dry-run.rb` for go_modules, npm_and_yarn, python, bundler, and cargo on both Nix-built and Ubuntu-based images, diff outputs, confirm identical results

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (flake + shared libraries) — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Phase 2 (core image must build)
- **US2 (Phase 4)**: Depends on Phase 2 (core image as fromImage). Can start in parallel with US1 validation tasks.
- **US3 (Phase 5)**: Depends on Phase 4 (ecosystem images must exist to overlay dev tools)
- **US4 (Phase 6)**: Depends on Phases 3+4 (core + ecosystem images validated before CI migration)
- **Polish (Phase 7)**: Depends on all user stories being validated

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational (Phase 2) — No dependencies on other stories
- **US2 (P2)**: Can start after Foundational (Phase 2) — Pilot ecosystems independent of US1 validation, but script/build changes from US1 are helpful
- **US3 (P3)**: Depends on US2 (needs ecosystem images to exist)
- **US4 (P4)**: Depends on US1 + US2 (needs validated core + ecosystem images before CI migration)

### Within Each User Story

- Nix definitions before validation
- Simple ecosystems before complex ones (within US2)
- Pilot validation before batch migration (within US2)
- Core implementation before integration

### Parallel Opportunities

- All Phase 1 tasks marked [P] can run in parallel (T004, T005, T006, T007)
- Within US2, all pilot ecosystems marked [P] can be developed in parallel (T026, T027, T028)
- Within US2, all remaining/minimal ecosystems marked [P] can be developed in parallel (T048–T062)
- Within US2, all independent validations marked [P] can run in parallel (T033–T034, T065–T068)
- Within US3, dev shell validations for different ecosystems marked [P] can run in parallel (T075, T076)
- Phase 7 documentation tasks marked [P] can run in parallel (T086, T087)

---

## Parallel Example: User Story 2 (Pilot)

```
# Launch all pilot ecosystem definitions together:
Task T026: "Implement silent ecosystem image in nix/ecosystems/silent.nix"
Task T027: "Implement docker ecosystem image in nix/ecosystems/docker.nix"
Task T028: "Implement bundler ecosystem image in nix/ecosystems/bundler.nix"

# After T031 (wire into flake), launch validations in parallel:
Task T033: "Validate docker ecosystem"
Task T034: "Validate bundler ecosystem"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T007)
2. Complete Phase 2: Foundational — core image (T008–T018)
3. Complete Phase 3: US1 — validate core as drop-in replacement (T019–T025)
4. **STOP and VALIDATE**: Core image passes updater RSpec, ecosystem Dockerfiles build against it
5. Decision point: proceed with ecosystem migration or iterate on core

### Incremental Delivery

1. Setup + Foundational → Core image buildable
2. US1 → Core validated as drop-in replacement (MVP!)
3. US2 pilot → 5 ecosystems validated on Nix
4. US2 full → All 30+ ecosystems on Nix
5. US3 → Dev shell works with Nix images
6. US4 → CI/CD fully migrated
7. Polish → Dockerfiles removed, docs updated

### Suggested MVP Scope

**Phases 1–3 (T001–T025)**: Core image built with Nix, validated against existing tests, build scripts support dual-path (Nix + Docker). This delivers proof-of-concept without touching any ecosystem Dockerfiles.
