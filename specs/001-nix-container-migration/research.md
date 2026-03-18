# Research: Nix Container Migration

**Feature**: 001-nix-container-migration
**Date**: 2026-03-18
**Purpose**: Resolve all technical unknowns from the implementation plan

---

## R1: nix2container Capabilities

**Decision**: Use nix2container (github.com/nlewo/nix2container) as the OCI image builder.

**Rationale**: It produces standard OCI images without writing tarballs to the Nix store, supports layering via `fromImage`/`layers`/`buildLayer`, integrates natively with Nix flakes, and is significantly faster than `dockerTools.buildImage` (~1.8s vs ~10s for incremental rebuilds). The project is ~5 years old with 800+ stars and active maintenance.

**Alternatives considered**:

- `dockerTools.buildImage` (nixpkgs built-in): Slower, writes full tarballs to the Nix store, less granular layering. Rejected.
- `dockerTools.streamLayeredImage` (nixpkgs): Better than `buildImage` but still slower than nix2container and less composable. Rejected.
- Continue with Dockerfiles: Doesn't solve the version management problem. Rejected.

**Key capabilities confirmed**:

- **Layering**: `buildImage` accepts `fromImage` (base image), `layers` (list of `buildLayer` results), and `copyToRoot`. Layers deduplicate store paths automatically.
- **Environment variables**: Set via `config.Env` (list of `"KEY=value"` strings) in the OCI image config.
- **User creation**: No built-in primitive. Create `/etc/passwd`, `/etc/group`, `/etc/shadow` via `pkgs.runCommand` and place with `copyToRoot`. Use `perms` attribute for ownership.
- **OCI output**: Produces a JSON descriptor (not a tarball). Transferred to Docker daemon/registry via bundled patched Skopeo with `nix:` transport.
- **COPY equivalent**: Use `copyToRoot` for files at `/`. Create Nix derivations (`runCommand`, `writeTextDir`) for arbitrary host files.
- **RUN equivalent**: No direct equivalent. Use Nix derivations (`runCommand`, `mkDerivation`) to run commands at build time. Output is a content-addressed store path included in the image. This is more reproducible than Docker `RUN`.

**Limitations**:

- No multi-arch manifests (build per-arch images, assemble manifest externally).
- Uses a custom Skopeo fork (`skopeo-nix2container`) — bundled, not stock Skopeo.
- Cannot run commands inside a container at build time (all commands run in Nix sandbox).
- macOS builds require a Linux remote builder or VM for producing Linux images.

---

## R2: nixpkgs Package Availability

**Decision**: Use a pinned nixpkgs unstable revision as the primary package source. Use an older nixpkgs pin or custom derivations for Python 3.9/3.10. Use a custom derivation or binary download for Swift 6.x.

**Rationale**: 27 of 30 required tools are available in nixpkgs unstable. The 3 gaps (Python 3.9, Python 3.10, Swift 6.x) have clear mitigation paths.

**Alternatives considered**:

- Use nixpkgs stable (24.11): Has even fewer cutting-edge packages. Rejected.
- Use Homebrew or other package managers inside the image: Defeats the purpose of Nix. Rejected.

### Availability summary

| Category | Available | Gaps |
|----------|-----------|------|
| System tools (git, git-lfs, bzr, hg, gnupg, openssh, ca-certificates, gcc/make, gmp, zlib, unzip, zstd, file, libyaml, locales) | 15/15 | None |
| Ruby 3.4.x | Yes | Exact patch (3.4.8) depends on nixpkgs revision |
| Go 1.26.x | Yes (`pkgs.go_1_26`) | None |
| Node.js 24.x + npm | Yes (`pkgs.nodejs_24`) | None |
| Python 3.11–3.14 | Yes | None |
| Python 3.9, 3.10 | **No** (removed from nixpkgs unstable, EOL) | Use older nixpkgs input or custom derivation |
| Rust 1.94.x | Yes (`pkgs.rustc` + `pkgs.cargo`) | None |
| Erlang 26 + Elixir | Yes (`pkgs.beam26Packages.erlang`) | None |
| OpenJDK 21 + Maven 3.9 | Yes (`pkgs.jdk21` + `pkgs.maven`) | None |
| Swift 6.2.x | **No** (nixpkgs at 5.10.1) | Custom derivation or binary fetch required |
| Dart/Flutter | Yes (`pkgs.flutter`) | None |
| corepack, pnpm, yarn-berry, cosign, regctl | Yes | None |

### Python multi-version strategy

Nix natively supports multiple Python versions as independent store paths. Each installs with a version-suffixed binary (`python3.11`, `python3.12`, etc.). No pyenv needed for version switching. However, the existing Ruby code calls `pyenv exec` — two migration options:

1. **Symlink shim**: Create pyenv-like directory structure at `$PYENV_ROOT/versions/` with symlinks to Nix-provided Python installations. The Ruby code continues to use `pyenv exec` unchanged.
2. **Replace pyenv calls**: Update the Ruby code to call versioned Python binaries directly. More invasive but cleaner long-term.

**Decision**: Option 1 (symlink shim) for the initial migration to minimize changes to Ruby source code. Option 2 as a follow-up.

### Swift 6.x strategy

Swift 6.x is not in nixpkgs (stuck at 5.10.1). Options:

1. **Fixed-output derivation**: Download the official Swift tarball (same approach as current Dockerfile) with a known hash. Place it at `/opt/swift/`.
2. **Overlay**: Maintain a Nix overlay that packages Swift 6.x from the official releases.
3. **Keep Dockerfile for swift**: During transition, keep the swift ecosystem on Dockerfiles.

**Decision**: Option 1 (fixed-output derivation). This directly mirrors what the current Dockerfile does and requires no upstream packaging work.

---

## R3: CI/CD Pipeline Strategy

**Decision**: Use `DeterminateSystems/nix-installer-action` + `DeterminateSystems/magic-nix-cache-action` for CI. Use native arm64 runners for multi-arch builds. Use a matrix strategy with ecosystem grouping.

**Rationale**: `magic-nix-cache-action` is zero-config, free, requires no secrets, and works on forks — critical for an open-source project accepting external PRs. Native arm64 runners avoid the 5–10x slowdown of QEMU emulation.

**Alternatives considered**:

- Cachix: Requires paid plan for private caching, needs secret management. Better suited as a secondary layer for developer machines. Rejected as primary.
- QEMU emulation for arm64: 5–10x slower for heavy builds. Rejected.
- Cross-compilation via `pkgsCross`: Unreliable for complex packages like Ruby, Python, Node.js. Rejected.

### CI architecture

```
GitHub Actions workflow
├── Job: build-core (matrix: [x86_64-linux, aarch64-linux])
│   ├── Install Nix + magic-nix-cache
│   ├── nix build .#core
│   └── Push to GHCR + cosign sign
├── Job: build-ecosystems (matrix: [ecosystem × arch], needs: build-core)
│   ├── Install Nix + magic-nix-cache
│   ├── nix build .#ecosystems.{name}
│   └── Push to GHCR + cosign sign
└── Job: test-ecosystems (matrix: [ecosystem], needs: build-ecosystems)
    ├── Pull Nix-built image
    └── docker run ... rspec spec
```

### Authentication for GHCR push

Use `docker login` or Skopeo's `--dest-creds` flag with `GITHUB_TOKEN`:

```bash
nix run .#myImage.copyTo -- \
  --dest-creds "$GITHUB_ACTOR:$GITHUB_TOKEN" \
  docker://ghcr.io/dependabot/dependabot-updater-core:latest
```

### Cosign signing

Cosign operates on images already in a registry. After `nix run .#image.copyTo` pushes the image, `cosign sign` signs it by digest. This is identical to the current workflow — the build tool is irrelevant to the signing step.

### Parallelism

Multiple `nix build` commands can run in parallel within a job (shared Nix store). For 30+ ecosystems, a matrix strategy across runners is more practical. Group 3–5 ecosystems per job to balance store sharing vs. parallelism.

---

## R4: Native Helper Build Scripts

**Decision**: Native helper build scripts will run as Nix derivations during image build. Helpers that work without modification will be wrapped in `runCommand`. Helpers that assume Ubuntu-specific paths will be patched.

**Rationale**: The helper build scripts (`{ecosystem}/helpers/build`) are shell scripts that invoke ecosystem-specific tooling (e.g., `go build`, `npm install`, `pip install`). Since the Nix image provides the same tools at the same or compatible paths, most scripts should work unchanged.

**Potential issues**:

- Scripts that reference `/etc/apt/` or Debian-specific paths: None found in helper scripts (these only exist in Dockerfiles).
- Scripts that expect specific directory layouts: Most use `$DEPENDABOT_NATIVE_HELPERS_PATH` (set to `/opt`) which is preserved.
- The Python helpers use `pyenv exec pip install` — this works if the pyenv symlink shim (R2) is in place.

---

## R5: git-shim Packaging

**Decision**: Package the git-shim as a Nix fixed-output derivation using its GitHub release URL and known hash.

**Rationale**: The git-shim is a single static binary downloaded from `github.com/dependabot/git-shim/releases`. Nix's `fetchurl` with a content hash is the idiomatic way to handle this.

```nix
git-shim = pkgs.fetchurl {
  url = "https://github.com/dependabot/git-shim/releases/download/v1.4.0/git-v1.4.0-linux-${arch}.tar.gz";
  sha256 = "...";
};
```

**Alternatives considered**:

- Build from source via Nix: Requires a Go build environment and more maintenance. Rejected for now since binaries are available.
- nixpkgs package: Not yet packaged. Rejected.

---

## R6: Transition Strategy

**Decision**: Coexistence phase where Dockerfiles and Nix definitions exist side-by-side. Ecosystems migrate one at a time. Both build paths remain functional until all ecosystems are validated.

**Rationale**: A big-bang migration of 30+ ecosystems is too risky. Per-ecosystem migration allows validating each one independently and rolling back if issues arise.

**Transition phases**:

1. Add `nix/` directory with core image definition. Validate against existing test suites.
2. Add Nix definitions for 3–5 pilot ecosystems (silent, docker, bundler, go_modules, npm_and_yarn). Validate.
3. Migrate remaining ecosystems batch by batch.
4. Update CI workflows to use Nix-built images.
5. Remove Dockerfiles once all ecosystems are validated.
6. Update `rake ecosystem:create` scaffolding.

---

## R7: Development Shell Compatibility

**Decision**: `bin/docker-dev-shell` continues to work by referencing Nix-built images loaded into the Docker daemon via `nix run .#devImage.copyToDockerDaemon`.

**Rationale**: The dev shell script ultimately runs `docker run` with volume mounts. It only needs to reference an image by name. Whether that image was built by `docker build` or loaded from a Nix-built OCI artifact is transparent.

**Changes required**:

- `bin/docker-dev-shell`: Update image name reference or add a flag to choose Nix-built images.
- `script/build`: Add Nix build path alongside Docker build path.
- `script/_common`: Update `docker_build()` function to support Nix-built images.
