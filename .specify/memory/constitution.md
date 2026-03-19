<!--
Sync Impact Report
==================
- Version change: 1.0.0 → 1.0.1 (PATCH: clarifications)
- Modified principles:
  - II. Container-Isolated Execution: "Docker containers" → "OCI containers"
- Modified sections:
  - Ecosystem Standards: "Dockerfile" → "build definition (e.g., Dockerfile or Nix expression)"
  - Ecosystem Standards: clarified centralized build definitions in nix/ are acceptable
- Removed sections: none
- Templates requiring updates:
  - .specify/templates/plan-template.md ✅ no changes needed
  - .specify/templates/spec-template.md ✅ no changes needed
  - .specify/templates/tasks-template.md ✅ no changes needed
- Follow-up TODOs: none
-->

# Dependabot Core Constitution

## Core Principles

### I. Plugin Architecture

The monorepo is organized as a collection of ecosystem gems built on
`dependabot-common`. Each ecosystem MUST implement the 7 core
interfaces: FileFetcher, FileParser, UpdateChecker, FileUpdater,
MetadataFinder, Version, and Requirement. Each interface MUST inherit
from its corresponding base class in `dependabot-common`. Ecosystems
MUST be self-contained and independently testable. New ecosystems MUST
be scaffolded via `rake ecosystem:create[name]` and follow the
directory convention `{ecosystem}/lib/dependabot/{ecosystem}/`.

### II. Container-Isolated Execution

All code execution—tests, dry-runs, native helpers—MUST occur inside
OCI containers. Host-system execution is not supported. The layered
container image hierarchy (updater-core → updater-ecosystem →
development) MUST be maintained. Images may be built with any
OCI-compatible toolchain (e.g., Docker, Nix + nix2container). Native
package manager helpers MUST be rebuilt inside the container after any
source change.

### III. Security-First Design

Private registry credentials MUST never be exposed directly to
Dependabot-Core. Production deployments MUST use the credential proxy
pattern so that secrets are injected at the proxy layer and stripped
on the return path. Manifest files (e.g., `setup.py`, `.gemspec`) can
execute arbitrary code; therefore, security boundaries between
credential handling and dependency resolution MUST be enforced at all
times. Security vulnerabilities MUST be disclosed through the GitHub
Bug Bounty program, not the public issue tracker.

### IV. Test-Accompanied Changes

Every feature addition or bug fix MUST include RSpec tests. Tests run
automatically on pull requests and MUST pass before merge. Style
enforcement via RuboCop is mandatory. Test and fixture files MUST
follow the convention
`{ecosystem}/spec/dependabot/{ecosystem}/` and
`{ecosystem}/spec/fixtures/` respectively. All file handling in tests
MUST use `Dependabot::DependencyFile` objects, never raw file content.

### V. Upstream Alignment

New major package manager versions MUST be supported within 1 quarter
of their release. New upstream features (e.g., new lockfile types)
MUST be supported within 2–4 quarters unless they are breaking
changes, in which case the 1-quarter window applies. Deprecated
upstream versions lose guaranteed support 3 months after upstream EOL.
Deprecation notices MUST be published via GitHub Changelog, and
warnings MUST be sent to affected users where possible.

## Ecosystem Standards

- Each ecosystem MUST reside in its own top-level directory containing
  a complete gem (gemspec, README, lib/, spec/, script/) and a build
  definition (e.g., a Dockerfile or a Nix expression under `nix/ecosystems/`).
- All file operations MUST use the `Dependabot::DependencyFile`
  abstraction (`name`, `content`, `directory`, `type`). Raw file
  content access is prohibited outside of parsers.
- Ecosystem-specific error classes MUST inherit from
  `Dependabot::DependabotError`. Network timeouts and rate limits are
  handled by the `common` layer and MUST NOT be re-implemented.
- Version classes MUST handle ecosystem-specific semantics
  (pre-releases, build metadata, `+incompatible` suffixes, etc.).
- Native helpers (small executables in the ecosystem's host language)
  MUST live in `{ecosystem}/helpers/` and MUST be rebuilt via their
  build script after any change.
- Adding a new ecosystem is a significant commitment. It MUST begin
  with a tracking issue and follow the phased process in
  `NEW_ECOSYSTEMS.md`.

## Development Workflow

- The development environment MUST use the container-based dev shell
  (`bin/docker-dev-shell {ecosystem}`).
- Contribution flow: fork → development environment → feature or
  fix → tests → pull request.
- Git commits MUST follow one-commit-per-logical-change. Squash merge
  is the default; merge commits are used only when a PR contains
  multiple commits that MUST NOT be squashed. Rebase merges are
  prohibited (they break `git bisect`).
- After addressing PR review feedback, the contributor MUST resolve
  the corresponding review threads.
- Bug reports MUST include a link to a public reproducing repository
  or a dry-run script invocation. Reports that cannot be reproduced
  may be closed.
- Refer to `CONTRIBUTING.md` for contribution details and
  `MAINTENANCE_STANDARDS.md` for support lifecycle policy.

## Governance

This constitution is the authoritative source for architectural and
process decisions in Dependabot Core. It supersedes ad-hoc or
informal practices where conflicts arise.

- **Amendments**: Any change to this constitution MUST be submitted as
  a pull request with a description of the change, its rationale, and
  a version bump following semantic versioning (MAJOR for principle
  removals/redefinitions, MINOR for additions/expansions, PATCH for
  clarifications).
- **Compliance**: All pull requests and code reviews MUST verify
  compliance with these principles. Violations MUST be flagged before
  merge.
- **Review cadence**: The constitution SHOULD be reviewed at least
  once per quarter to ensure alignment with upstream ecosystem changes
  and project evolution.
- **Runtime guidance**: `CONTRIBUTING.md`, `MAINTENANCE_STANDARDS.md`,
  and `NEW_ECOSYSTEMS.md` provide operational details that complement
  this constitution.

**Version**: 1.0.1 | **Ratified**: 2026-03-18 | **Last Amended**: 2026-03-18
