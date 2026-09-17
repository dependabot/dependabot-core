---
name: create-dependency-grapher
description: >-
  Use when adding dependency-graph (GitHub Dependency Submission API) support to a Dependabot
  ecosystem gem that doesn't have a DependencyGrapher yet, or when extending an existing one —
  "add a DependencyGrapher to X", "add dependency graph support for X", "implement subdependency
  fetching for the X grapher", "does X need ephemeral lockfile generation", "does X need manifest
  grouping / layering". Walks through implementing the grapher class, tests, subdependency
  fetching, manifest grouping (layering) for ecosystems with multiple independent manifests per
  directory, and ephemeral lockfile generation, using Go, Python, and npm/yarn/pnpm as reference
  implementations.
compatibility: >-
  Requires a local checkout of dependabot-core. The Code Review Tasks run `bin/test
  {ecosystem}`, `bin/test {ecosystem} rubocop -A`, and containerized `bundle exec srb tc`, which
  expect this repo's Docker-based ecosystem tooling to be available (see the repo's own
  CONTRIBUTING docs for setup).
---

# Create Dependency Grapher

Interactive assistant for adding a `DependencyGrapher` to an existing Dependabot ecosystem gem.

## Overview

A DependencyGrapher converts parsed dependencies into a standardized graph structure based on GitHub's [Dependency Submission API](https://docs.github.com/en/rest/dependency-graph/dependency-submission). Each ecosystem that supports dependency graphing implements a class inheriting from `Dependabot::DependencyGraphers::Base`.

This skill guides you through implementing a new grapher step-by-step, asking questions to determine the right approach for your ecosystem.

## Boundaries

**Will:**
- Ask the ecosystem-specific questions needed to scope the work (PURL type, ephemeral lockfiles, manifest layering) before writing code.
- Guide an iterative build — basic grapher → tests → subdependency fetching → (optionally) manifest grouping → (optionally) ephemeral lockfile generation — with a code review checkpoint after each stage.
- Always run the ecosystem's test suite, lint, and Sorbet type-check before handing back for review (see "Code Review Tasks").

**Will Not:**
- Alter the ecosystem's `FileParser`. Changing the parser risks introducing bugs or added latency for Dependabot's core update functionality — if the grapher needs information the parser doesn't return, retrieve it in the grapher itself, even if that means re-parsing a file.
- Skip a code review checkpoint between iterations, even if asked to "just finish it" — each checkpoint is a natural point to test against real projects before building further on top.
- Implement manifest grouping or ephemeral lockfile generation for an ecosystem that doesn't need them.

## When to Use

Use this skill when you need to:

- Add dependency graph support to an ecosystem that doesn't have it yet
- Understand the DependencyGrapher pattern before implementing one
- Determine whether an ecosystem needs ephemeral lockfile generation or manifest layering

## Detailed Instructions

### Determine the target ecosystem

Ask the user which ecosystem gem needs a DependencyGrapher? (e.g., `bundler`, `cargo`, `composer`, `hex`)

### Investigate the FileParser to learn about the ecosystem

The file parser will exist at: `{ecosystem}/lib/dependabot/{ecosystem}/file_parser.rb`

The tests for the file parser will exist at: `{ecosystem}/spec/dependabot/{ecosystem}/file_parser_spec.rb`

From the files determine the following:

- What is a typical manifest file for the ecosystem?
- What is a typical lock file for the ecosystem?
- Do we parse projects that have only the manifest file checked in?
- Are there multiple packager managers involved in this ecosystem?
- Do we use the native binary for each package manager involved?
- Can a single directory routinely contain **multiple independent manifests** that should each be reported as their own snapshot, rather than being merged into one?
  - Examples:
    - Python's `base-requirements.txt` + `test-requirements.txt`
    - GitHub Actions' `.github/workflows/` directory with several independent workflow files
  - This is the "layering" case covered in the Implement Manifest Grouping step below.

### Gather requirements

If the user's initial request already answers a question in this section (e.g. it confirms or
rules out multiple manifests per directory, or states whether a lockfile is always committed),
use that answer directly and do not re-ask it.

#### PURLs for the ecosystem

1. Refer to the [Package-URL type](https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst) list to find a recommended type for this ecosystem (e.g., `gem`, `cargo`, `composer`, `hex`). Ask the user to confirm if this type is correct or to provide an alternative.

2. Ask the user if this ecosystem uses version prefixes in PURLs (e.g., Go uses `v` prefix: `@v1.2.3`)

#### Ephemeral lockfiles

If the ecosystem uses lockfiles and we parse projects that have only the manifest checked in, for each package manager involved ask the user:

- For {package_manager} should we generate ephemeral lockfiles?

#### Layered / multi-manifest directories

Based on the answer from the Investigate the FileParser step, ask the user:

- Can this ecosystem have more than one independent manifest checked into the same directory, where each one should be attributed its own snapshot?

If yes, note that basic functionality (Create the Grapher Class / Create a test for the Grapher Class) should still only address the common single-manifest case; layering support is added later in the Implement Manifest Grouping step, once the basic grapher is working.

### Create the Grapher Class

For this step, only basic functionality should be addressed, we should ignore subdependency fetching and ephemeral lockfiles.

Create the file at: `{ecosystem}/lib/dependabot/{ecosystem}/dependency_grapher.rb`

The class must:

1. Inherit from `Dependabot::DependencyGraphers::Base`
2. Use `# typed: strict` and Sorbet signatures throughout
3. Implement the three required abstract methods:
   - `relevant_dependency_file` — Returns the `DependencyFile` to report against (prefer lockfile, fallback to manifest)
   - `fetch_subdependencies(dependency)` — Returns an empty array for now
   - `purl_pkg_for(dependency)` — Returns the PURL type string for this ecosystem
4. Optionally override:
   - `purl_name_for(dependency)` — If the dependency name needs normalisation for PURLs
   - `purl_version_for(dependency)` — If the ecosystem uses version prefixes
5. Register the grapher at the bottom of the file, and require it from the ecosystem's main entry point (or confirm it's autoloaded), so it's actually wired up:
   ```ruby
   Dependabot::DependencyGraphers.register("{ecosystem_key}", Dependabot::{Module}::DependencyGrapher)
   ```

### Create a test for the Grapher Class

Create the spec at: `{ecosystem}/spec/dependabot/{ecosystem}/dependency_grapher_spec.rb`

Tests should cover:

1. **`#relevant_dependency_file`** — Returns the correct file (lockfile when present, manifest as fallback)
2. **`#resolved_dependencies`** — Returns correctly structured `ResolvedDependency` objects with:
   - Valid PURLs
   - Correct `direct` flag (top-level vs transitive)
   - Correct `runtime` flag (production vs development)
   - An empty `dependencies` array
3. **Error handling** — Verify graceful degradation when:
   - Native commands fail
   - Lockfile is malformed

### Code review

Run the checklist in Code Review Tasks below, then ask the user to review your work and tell you
when to continue with the next step.

You should suggest some best practice to the user at this point:
- Consider opening a PR with the work so far and testing it against a range of projects for correctness
- Start a new branch to implement subdependency fetching as an iteration

When they ask you to continue read the implementation and tests to see what improvements they have made.

### Implement subdependency fetching

1. Write a test for the desired subdependency fetching behaviour for this ecosystem
2. Confirm that the test fails since `fetch_subdependencies(dependency)` is hard-coded to return an empty array for now.
3. Implement `fetch_subdependencies(dependency)` using one of these strategies in order of preference:
  - Use data already present on the `resolved_dependencies` if the `FileParser` already extracts this information.
  - Reparsing the lockfile using the package manager's `LockFileParser` to extract this information
  - Using a native package manager command to obtain structured dependency relationship data
  - Using a generic parser for the file type to obtain the data ( e.g. `json`, `yaml` or `toml` parsing )
4. Verify the test now passes
5. Assess the need for test coverage for failure modes reading data in `fetch_subdependencies(dependency)`:
  - We should always log these errors and make sure error flags are set on the grapher so the job runner knows the data is degraded

### Code review

Run the checklist in Code Review Tasks below, then ask the user to review your work.

If neither manifest grouping (layering) nor ephemeral lockfile generation is required, we are now finished - otherwise we need to proceed to the next step(s).

### Implement manifest grouping (layering)

Only relevant if the Gather Requirements step determined the ecosystem can have multiple
independent manifests in the same directory. If not, skip straight to ephemeral lockfile
generation (or finish, if that isn't needed either).

Read [`references/manifest-layering.md`](references/manifest-layering.md) and follow its
procedure: it covers writing the failing test first, overriding `manifest_groups` with the
fall-back-to-`super` pattern, and the edge cases to add coverage for.

### Code review

Run the checklist in Code Review Tasks below, then ask the user to review your work.

If ephemeral lockfile generation is not required, we are now finished - otherwise we need to proceed to the next step.

### Prepare for Ephemeral Lockfile Generation

If ephemeral lockfile generation is required, ask the user to tell you when they are ready to start and suggest they
open a PR with the work so far to test it.

When they ask you to continue read the implementation and tests to see what improvements they have made.

### Implement Ephemeral Lockfile Generation

Read [`references/ephemeral-lockfiles.md`](references/ephemeral-lockfiles.md) and follow its
procedure: it covers writing the failing test first, the `LockfileGenerator` class shape, the
`prepare!` override pattern, and the failure-mode test coverage to add.

### Code review

Run the checklist in Code Review Tasks below, then ask the user to verify your work, we are now
finished.

## Code Review Tasks

As part of each code review step, before prompting the user to review changes you must always:

1. Run the ecosystem's test suite and fix any failures:

```
bin/test {ecosystem} spec/dependabot/{ecosystem}
```

2. Check lint and fix any problems:

```
bin/test {ecosystem} rubocop -A
```

3. Run sorbet and fix any problems:

```
bundle exec srb tc
```

## References

Documentation for `DependencyGrapher` implementation is available in this repository at:

`common/lib/dependabot/dependency_graphers/README.md` — read this first if you need a refresher
on the `resolved_dependencies` / `manifest_groups` API before starting.

`references/manifest-layering.md` and `references/ephemeral-lockfiles.md` in this skill's own
directory hold the detailed, step-by-step procedures for those two optional features — read the
relevant one only when the Gather Requirements step determines it's needed (see the Detailed
Instructions above for exactly when to load each).

## Reference Implementations

Use these as models when implementing:

| Ecosystem | Key File |
|-----------|----------|
| **Go** | `go_modules/lib/dependabot/go_modules/dependency_grapher.rb` |
| **Python** | `python/lib/dependabot/python/dependency_grapher.rb` |
| **npm/yarn/pnpm** | `npm_and_yarn/lib/dependabot/npm_and_yarn/dependency_grapher.rb` |
| **Python** (pip/pip-compile requirements layers) | `python/lib/dependabot/python/dependency_grapher/requirements_layers.rb` |

## Gotchas

Concrete pitfalls that don't follow from general Ruby/Sorbet knowledge — read these before
writing code, not after debugging a failure:

- **Never mutate a shared `DependencyFile` to mark it as a support file.** When building a
  `ManifestGroup`'s `files:` list, a sibling file pulled in only for cross-referencing must be
  copied with `support_file: true`, not have its existing `DependencyFile` instance mutated —
  other groups may still need that same file with its original attributes. See
  `as_support_file` in `python/lib/dependabot/python/dependency_grapher/requirements_layers.rb`.
- **`scoped_grapher` (used by `manifest_group_snapshots` for multi-group directories) calls
  `file_parser.class.new(dependency_files:, source:, repo_contents_path:, credentials:,
  reject_external_code:, options:)`.** If the ecosystem's `FileParser` constructor doesn't accept
  every one of those keyword arguments, layering will raise at runtime instead of failing a type
  check — confirm the parser's signature matches before assuming `manifest_groups` will work.
- **When one grapher must support several package managers** (Python's pip / pip-compile /
  Pipenv / Poetry all share one `DependencyGrapher`), route behavior off a single detector method
  (Python's `python_package_manager`) rather than re-deriving "which package manager is this"
  independently in every method — it's easy for two of those checks to quietly drift out of sync.
- **An ephemeral lockfile must never become `relevant_dependency_file`.** If you inject a
  generated lockfile into `dependency_files` for parsing, keep a separate "was this file
  committed?" check (e.g. Python's `committed_poetry_lock` returning `nil` once
  `@ephemeral_lockfile_generated` is set) so attribution still points at the real manifest.
- **`purl_name_for` is not just `dependency.name`.** Some ecosystems need to strip syntax that
  isn't part of the package identity before building a PURL — e.g. Python strips `[extras]` via
  `NameNormaliser.normalise`. Check whether your ecosystem's dependency names can carry anything
  beyond the bare package name before assuming the default implementation is correct.

## Example Prompts


### Adding a grapher to a new ecosystem

```
I need to add a DependencyGrapher to the Cargo ecosystem.
```

### Understanding the pattern first

```
Explain how DependencyGraphers work before I implement one for Hex.
```

### Focusing on ephemeral lockfile support

```
Add a DependencyGrapher to Composer. composer.lock may not always be committed, so we
probably need ephemeral lockfile generation.
```

### Focusing on layered/multi-manifest directories

```
Add a DependencyGrapher to GitHub Actions. A .github/workflows/ directory can hold several
independent workflow files, each with its own action dependencies.
```

## Edge Cases and Limitations

- **Multiple lockfile formats**: Some ecosystems (like Python) support multiple package managers. Your grapher may need to handle different lockfile formats.
- **Scoped/namespaced packages**: If your ecosystem has scoped names (like npm's `@scope/pkg`), ensure `purl_name_for` handles URL-encoding correctly.
- **Multiple versions of same package**: The base grapher resolves `fetch_subdependencies` results by package name and cannot distinguish multiple versions. Follow npm/yarn/pnpm's `resolved_dependencies` / `subdependency_purls_for` override to emit version-specific entries and PURL edges.
- **PURL spec compliance**: Always check [PURL-TYPES.rst](https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst) for your ecosystem's conventions.
- **Multiple independent manifests per directory**: Ecosystems that allow several independent manifests in one directory (e.g. Python's layered requirements, or a future GitHub Actions grapher covering multiple workflow files under `.github/workflows/`) need `manifest_groups` overridden so each manifest gets its own snapshot instead of being merged into one — see [`references/manifest-layering.md`](references/manifest-layering.md).
