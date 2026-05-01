---
name: create-dependency-grapher
description: Interactive DependencyGrapher creator skill that walks through the normal development process to add this component to an existing Dependabot ecosystem gem. It will ask you which ecosystem you need to add a grapher to, whether or not this ecosystem requires ephemeral lockfile generation, and iterates through a series of development steps using Go, Python and npm as reference implementations.
---

# Create Dependency Grapher

Interactive assistant for adding a `DependencyGrapher` to an existing Dependabot ecosystem gem.

## Overview

A DependencyGrapher converts parsed dependencies into a standardized graph structure based on GitHub's [Dependency Submission API](https://docs.github.com/en/rest/dependency-graph/dependency-submission). Each ecosystem that supports dependency graphing implements a class inheriting from `Dependabot::DependencyGraphers::Base`.

This skill guides you through implementing a new grapher step-by-step, asking questions to determine the right approach for your ecosystem.

## When to Use

Use this skill when you need to:

- Add dependency graph support to an ecosystem that doesn't have it yet
- Understand the DependencyGrapher pattern before implementing one
- Determine whether an ecosystem needs ephemeral lockfile generation

## Detailed Instructions

### Step 1: Determine the target ecosystem

Ask the user which ecosystem gem needs a DependencyGrapher? (e.g., `bundler`, `cargo`, `composer`, `hex`)

### Step 2: Investigate the FileParser to learn about the ecosystem

The file parser will exist at: `{ecosystem}/lib/dependabot/{ecosystem}/file_parser.rb`

The tests for the file parser will exist at: `{ecosystem}/spec/dependabot/{ecosystem}/file_parser_spec.rb`

From the files determine the following:

- What is a typical manifest file for the ecosystem?
- What is a typical lock file for the ecosystem?
- Do we parse projects that have only the manifest file checked in?
- Are there multiple packager managers involved in this ecosystem?
- Do we use the native binary for each package manager involved?

### Step 3: Gather requirements

#### PURLs for the ecosystem

1. Refer to the [Package-URL type](https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst) list to find a recommended type for this ecosystem (e.g., `gem`, `cargo`, `composer`, `hex`). Ask the user to confirm if this type is correct or to provide an alternative.

2. Ask the user if this ecosystem uses version prefixes in PURLs (e.g., Go uses `v` prefix: `@v1.2.3`)

#### Ephemeral lockfiles

If the ecosystem uses lockfiles and we parse projects that have only the manifest checked in, for each package manager involved ask the user:

- For {package_manager} should we generate ephemeral lockfiles?

### Step 3: Create the Grapher Class

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
5. Register the grapher at the bottom of the file:
   ```ruby
   Dependabot::DependencyGraphers.register("{ecosystem_key}", Dependabot::{Module}::DependencyGrapher)
   ```

### Step 4: Create a test for the Grapher Class

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

### Step 5: Code review

Ask the user to review your work and tell you when to continue with the next step.

You should suggest some best practice to the user at this point:
- Consider opening a PR with the work so far and testing it against a range of projects for correctness
- Start a new branch to implement subdependency fetching as an iteration

When they ask you to continue read the implementation and tests to see what improvements they have made.

### Step 6: Implement subdependency fetching

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

### Step 7: Code review

Ask the user to review your work.

If ephemeral lockfile generation is not required, we are now finished - otherwise we need to proceed to the next step.

### Step 8: Prepare for Ephemeral Lockfile Generation

If ephemeral lockfile generation is required, ask the user to tell you when they are ready to start and suggest they
open a PR with the work so far to test it.

When they ask you to continue read the implementation and tests to see what improvements they have made.

### Step 9: Implement Ephemeral Lockfile Generation

1. Write a test for the desired behaviour when a project has no lockfile checked in:
  - We should still get transitive dependencies only present in the lockfile
  - We should still get subdepednencies
2. Confirm that this test fails since we only parse the manifest file for now.
3. Create a nested class to generate a lockfile:
  `{ecosystem}/lib/dependabot/{ecosystem}/dependency_grapher/lockfile_generator.rb`

  This class should:
    1. Accept `dependency_files:` and `credentials:` (and any ecosystem-specific params)
    2. Implement a `generate` method that returns a `Dependabot::DependencyFile`
    3. Run the ecosystem's native lock command in a temporary directory
    4. Return a `DependencyFile` object with the generated lockfile content

  In the main grapher, override `prepare!` to:
    1. Detect when a lockfile is missing
    2. Call the generator
    3. Inject the ephemeral lockfile into `dependency_files`
    4. Set `@ephemeral_lockfile_generated = true`
    5. Call `super` to proceed with normal parsing
    6. Rescue errors and call `errored_fetching_subdependencies!`

4. Verify that the test we added for the `DependencyGrapher` now passes.
5. Add a test file for the lockfile generator:
  `{ecosystem}/spec/dependabot/{ecosystem}/dependency_grapher/lockfile_generator_spec.rb`
6. Add test coverage for failure modes around ephemeral lockfile generation:
  - Generation failure doesn't crash the grapher
  - Generated lockfile is not reported as `relevant_dependency_file`


### Step 10: Code review

As the user to verify your work, we are now finished.

## Code Review Tasks

As part of each code review step, before prompting the user to review changes you must always:

1. Run the ecosystem's test suite and fix any failures:

```
bin/test {ecosystem} spec/dependabot/{ecosystem}
```

2. Check lint and fix any problems:

```
bin/lint -a {created or changed files}
```

3. Run sorbet and fix any problems:

```
bundle exec srb tc -a
```

### Step 5: Wire Up Registration

Ensure the grapher is loaded by the ecosystem. Add a require to the ecosystem's main entry point or ensure it's autoloaded:

```ruby
require "dependabot/{ecosystem}/dependency_grapher"
```

### Step 6: Verify

Run the ecosystem's test suite to confirm:

```bash
# From within the ecosystem's Docker container
cd {ecosystem} && bundle exec rspec spec/dependabot/{ecosystem}/dependency_grapher_spec.rb
```

## References

Documentation for `DependencyGrapher` implementation is available in this repository at:

`common/lib/dependabot/dependency_graphers/README.md`

## Reference Implementations

Use these as models when implementing:

| Ecosystem | Key File |
|-----------|----------|
| **Go** | `go_modules/lib/dependabot/go_modules/dependency_grapher.rb` |
| **Python** | `python/lib/dependabot/python/dependency_grapher.rb` |
| **npm/yarn/pnpm** | `npm_and_yarn/lib/dependabot/npm_and_yarn/dependency_grapher.rb` |

See the `references/` directory for annotated code from these implementations.

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
I need to add a grapher to Composer, and it needs ephemeral lockfile generation
since composer.lock may not always be committed.
```

## Edge Cases and Limitations

- **Multiple lockfile formats**: Some ecosystems (like Python) support multiple package managers. Your grapher may need to handle different lockfile formats.
- **Scoped/namespaced packages**: If your ecosystem has scoped names (like npm's `@scope/pkg`), ensure `purl_name_for` handles URL-encoding correctly.
- **Multiple versions of same package**: If your ecosystem allows multiple versions of a single dependency, `fetch_subdependencies` **must** return PURLs (not just names) to be unambiguous.
- **PURL spec compliance**: Always check [PURL-TYPES.rst](https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst) for your ecosystem's conventions.
