# Feature Specification: Nix Container Migration

**Feature Branch**: `001-nix-container-migration`
**Created**: 2026-03-18
**Status**: Draft
**Input**: User description: "Migrate docker containers from Ubuntu 24.04 to NixOS, and migrate from building with Docker and Dockerfiles to building with nix and nix2container. The issue is Dependabot requires a lot of external tooling that it expects to be there, and it needs to shell out to. However, a lot of that tooling is either vastly outdated in the LTS version of Ubuntu or requires us to manually install it. Nix would allow us to more centrally and easily manage this."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Core Image Built with Nix (Priority: P1)

An infrastructure maintainer replaces the existing `Dockerfile.updater-core` with a Nix-based build definition that produces an OCI-compatible container image. The resulting image contains all of the system-level dependencies currently installed via `apt-get` (git, git-lfs, mercurial, bzr, gnupg2, openssh-client, ca-certificates, build-essential, compression utilities, locale data) plus Ruby, and passes the same smoke tests the current image passes. The image is published to the same container registry path so downstream ecosystem images and the development shell continue to work without modification.

**Why this priority**: The core image is the foundation for every ecosystem image and the development shell. Nothing else can migrate until this layer is reproducible via Nix.

**Independent Test**: Build the Nix-defined core image, start a container from it, and verify that every binary currently expected on `$PATH` is present and at an equal or newer version, that `ruby --version` reports the expected release, and that `git`, `git-lfs`, `bzr`, `hg`, `gpg2`, and `ssh` all execute without error. Run the existing `updater/` RSpec suite inside the image.

**Acceptance Scenarios**:

1. **Given** the Nix build definition for the core image, **When** the image is built, **Then** it produces an OCI image that can be loaded by Docker or pushed to GHCR.
2. **Given** a container started from the Nix core image, **When** the updater RSpec tests are executed, **Then** all tests that pass on the current Ubuntu-based image also pass.
3. **Given** the Nix core image, **When** any ecosystem Dockerfile references it as `FROM`, **Then** the ecosystem image builds and runs without modification to the ecosystem Dockerfile.
4. **Given** the Nix build definition, **When** a dependency version is changed in the Nix expression, **Then** only the affected layers are rebuilt while unchanged layers are cached.

---

### User Story 2 - Ecosystem Images Built with Nix (Priority: P2)

An ecosystem maintainer converts an ecosystem-level Dockerfile (e.g., go_modules, npm_and_yarn, python, bundler) to a Nix build definition that layers ecosystem-specific tooling on top of the Nix-based core image. Each ecosystem image is built independently and contains the exact versions of language runtimes, package managers, and native helpers currently specified in its Dockerfile.

**Why this priority**: Once the core image is stable, ecosystem images are the next layer. Migrating them proves that Nix can handle the diverse toolchain requirements (Go, Node.js, multiple Python versions via pyenv, pnpm, yarn, corepack, etc.) and that the native helper build scripts still work.

**Independent Test**: For a given ecosystem, build its Nix-defined image, start a container, verify the expected language runtime and package manager are present at the correct versions, then run `rspec spec` for that ecosystem inside the container.

**Acceptance Scenarios**:

1. **Given** a Nix build definition for the go_modules ecosystem, **When** the image is built, **Then** `go version` inside the container reports the expected Go version and the native helpers build script completes successfully.
2. **Given** a Nix build definition for the npm_and_yarn ecosystem, **When** the image is built, **Then** `node --version`, `npm --version`, `pnpm --version`, and `yarn --version` all report the expected versions.
3. **Given** a Nix build definition for the python ecosystem, **When** the image is built, **Then** all pre-installed Python versions are available through pyenv and the native helpers build for each version.
4. **Given** any migrated ecosystem image, **When** the ecosystem's full RSpec suite is executed, **Then** all tests that pass on the current Ubuntu-based image also pass.

---

### User Story 3 - Development Shell via Nix (Priority: P3)

A contributor uses `bin/docker-dev-shell {ecosystem}` and enters a container that was built via the Nix pipeline. The development shell includes all debugging and development tools (vim, strace, ltrace, gdb, shellcheck, libgit2-dev, cmake, pkg-config) in addition to the ecosystem tooling. The contributor can edit source code on the host, run tests and dry-runs inside the container, and rebuild native helpers—just as they can today.

**Why this priority**: The developer experience must remain intact for contributors. This story is lower priority because it depends on both the core and ecosystem images already being migrated, and it is an internal-only concern rather than a production-facing one.

**Independent Test**: Run `bin/docker-dev-shell go_modules`, verify the prompt appears, run `rspec spec` and `bin/dry-run.rb go_modules rsc/quote` inside the container, confirm both produce the expected output.

**Acceptance Scenarios**:

1. **Given** a Nix-built development image, **When** a contributor runs `bin/docker-dev-shell go_modules`, **Then** they land in an interactive shell with all expected tools on `$PATH`.
2. **Given** a running development container, **When** the contributor edits a Ruby source file on the host, **Then** the change is immediately reflected inside the container via the volume mount.
3. **Given** a running development container, **When** the contributor runs `bin/dry-run.rb` for any ecosystem, **Then** the dry-run completes with the same output as on the current Ubuntu-based image.

---

### User Story 4 - CI/CD Pipeline Produces Nix Images (Priority: P4)

The CI/CD pipeline is updated so that container images are built via Nix instead of `docker build`. The pipeline publishes multi-arch (amd64, arm64) OCI images to GHCR. Build caching via the Nix store reduces image rebuild times compared to the current Docker layer caching.

**Why this priority**: This is the final step to fully retire the Dockerfile-based pipeline. It depends on all previous stories being validated.

**Independent Test**: Trigger the CI build, verify images for at least two ecosystems are published to GHCR, pull them on both amd64 and arm64 hosts, and run a basic smoke test.

**Acceptance Scenarios**:

1. **Given** a push to the main branch, **When** the CI pipeline runs, **Then** Nix-based OCI images are built and published to GHCR for every ecosystem.
2. **Given** a CI run where only one ecosystem's Nix expression changed, **When** the pipeline completes, **Then** only that ecosystem's image is rebuilt; other ecosystem images are served from cache.
3. **Given** the published images, **When** they are pulled on an arm64 host, **Then** they run correctly without emulation.

---

### Edge Cases

- What happens when a native helper build script assumes Ubuntu-specific paths (e.g., `/usr/share/keyrings`, `/etc/apt/`)? The Nix image must provide equivalent paths or the helper scripts must be patched.
- What happens when an ecosystem pins a dependency to a Debian/Ubuntu package that does not exist in the Nix package set? A Nix overlay or custom derivation must be created.
- How does the system handle the `DEPENDABOT` environment variable check that downstream CI users rely on? The Nix image must continue to set `DEPENDABOT=true`.
- What happens when a contributor on macOS/ARM builds an image locally? The Nix pipeline must support cross-compilation or transparent emulation for linux/amd64 targets.
- What happens when the git-shim binary (currently downloaded as a platform-specific tarball) is not available as a Nix package? It must either be packaged as a Nix derivation or fetched as a fixed-output derivation with a known hash.
- How does the system handle the `pyenv` workflow in the Python ecosystem, which currently copies pre-compiled binaries from Docker Hub Python images? The Nix build must provide equivalent Python installations at the same paths pyenv expects, or the Ruby code that calls `pyenv exec` must be updated.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The build system MUST produce OCI-compatible container images from Nix expressions using nix2container, without requiring traditional Dockerfiles.
- **FR-002**: The Nix-built core image MUST contain all binaries currently installed in `Dockerfile.updater-core`: git, git-lfs, bzr, hg, gnupg2, openssh-client, ca-certificates, build-essential (gcc, make, etc.), zlib, unzip, zstd, file, libyaml, and locale data for `en_US.UTF-8`.
- **FR-003**: The Nix-built core image MUST include the same Ruby version currently used (Ruby 3.4.x) with RubyGems and Bundler at compatible versions.
- **FR-004**: Each ecosystem's Nix build definition MUST layer ecosystem-specific tooling on top of the core image, preserving the current layered image architecture (core → ecosystem → development).
- **FR-005**: The Nix build MUST support pinning every dependency to an exact version, so that builds are reproducible across machines and time.
- **FR-006**: The build system MUST continue to produce images compatible with the existing `bin/docker-dev-shell` workflow, including volume mounts for host-to-container source code access.
- **FR-007**: The Nix build MUST set all environment variables currently set in the Dockerfiles: `DEPENDABOT=true`, `DEPENDABOT_HOME`, `DEPENDABOT_NATIVE_HELPERS_PATH`, `GIT_LFS_SKIP_SMUDGE=1`, `PATH` entries, and ecosystem-specific variables (e.g., `NODE_EXTRA_CA_CERTS`, `NPM_CONFIG_AUDIT`, `REQUESTS_CA_BUNDLE`).
- **FR-008**: Native helper build scripts (`{ecosystem}/helpers/build`) MUST produce correct output when executed either as Nix derivations at image-build time (in the Nix sandbox) or inside the running container. Any helper that cannot build in the Nix sandbox MUST be documented and built at container-start time instead. Any modifications to helper scripts required for Nix compatibility MUST be documented and implemented as part of this feature.
- **FR-009**: The Nix build MUST support producing images for multiple architectures (at minimum amd64 and arm64) as separate per-arch images. Multi-arch OCI image index (manifest list) assembly is optional and may be added as a follow-up.
- **FR-010**: The `dependabot` user (UID 1000, GID 1000) MUST exist in the Nix-built images with the same home directory (`/home/dependabot`) and permissions as in the current images.
- **FR-011**: The Nix build MUST produce images that can be pushed to GHCR (`ghcr.io/dependabot/`) using the same tag naming conventions as today.
- **FR-012**: The migration MUST include a transition period where both Dockerfile-based and Nix-based images can be built, allowing ecosystem-by-ecosystem migration rather than requiring a single cutover.
- **FR-013**: The Nix package set MUST provide equal or newer versions of all external tools compared to what is currently installed via `apt-get` and manual downloads.
- **FR-014**: The `rake ecosystem:create[name]` scaffolding command MUST be updated to generate a Nix build definition alongside or instead of a Dockerfile for new ecosystems.

### Key Entities

- **Core Image Definition**: The Nix expression that replaces `Dockerfile.updater-core`. Contains system-level dependencies, Ruby, the `dependabot` user, and the git-shim. All ecosystem images depend on it.
- **Ecosystem Image Definition**: A per-ecosystem Nix expression that replaces each ecosystem's `Dockerfile`. Layers language runtimes, package managers, and native helpers on top of the core image.
- **Development Image Definition**: The Nix expression that replaces `Dockerfile.development`. Adds debugging/development tools to any ecosystem image.
- **Dependency Pin Set**: A centralized Nix configuration (e.g., a `flake.lock` or pinned nixpkgs revision) that locks all package versions for reproducibility.
- **Native Helper**: Small executables in each ecosystem's host language (e.g., Go, Node.js, Python) that Dependabot shells out to. Located in `{ecosystem}/helpers/`. Must build and run inside the Nix-built image.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of existing RSpec tests across all ecosystems pass when run inside Nix-built images, with zero regressions compared to the Ubuntu-based images.
- **SC-002**: Every external tool version in the Nix-built images is equal to or newer than the corresponding tool in the current Ubuntu 24.04-based images.
- **SC-003**: A contributor can go from a clean checkout to a running development shell in under 10 minutes using pre-built Nix images (matching or improving on the current Docker pull + shell startup time).
- **SC-004**: Changing a single ecosystem dependency version and rebuilding takes no longer than the current Dockerfile-based rebuild time for the same change.
- **SC-005**: The total number of lines of build configuration (Nix expressions) is no greater than the total number of lines across all current Dockerfiles, indicating that the build system has not become more complex.
- **SC-006**: All 30+ ecosystem images can be built from a single `nix build` invocation with proper caching, rather than requiring sequential `docker build` commands.
- **SC-007**: A version bump of any external tool (e.g., Go, Node.js, Python) requires changing exactly one line in the Nix configuration, compared to the current process of editing Dockerfile ARGs and potentially multiple files.
- **SC-008**: Dry-run scripts (`bin/dry-run.rb`) produce identical output for at least 5 representative ecosystems when run inside Nix-built vs. Ubuntu-based images.

## Assumptions

- The nixpkgs package set contains packages for all major tools Dependabot depends on (git, git-lfs, mercurial, bzr, Go, Node.js, Python, Ruby, etc.). For any tool not in nixpkgs, a custom Nix derivation will be written.
- The `nix2container` project is mature enough for production use. It supports producing multi-arch OCI images and integrates with standard container registries.
- The `pyenv` workflow in the Python ecosystem can be adapted to use Nix-provided Python installations at the paths pyenv expects, without rewriting the Ruby code that calls `pyenv exec`.
- The git-shim binary can be packaged as a Nix fixed-output derivation using its known release URL and hash.
- CI runners have Nix available or it can be installed as a bootstrap step. GitHub Actions runners support Nix installation via community actions.
- The existing `bin/docker-dev-shell` script can be adapted to load Nix-built images by changing the image name/tag it references, without fundamental workflow changes.
- ARM64 support in Nix and nix2container is sufficient for building linux/arm64 images, either natively or via cross-compilation.
