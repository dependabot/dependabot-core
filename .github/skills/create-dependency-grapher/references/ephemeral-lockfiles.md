# Implementing ephemeral lockfile generation

Load this file when the Gather Requirements step determined the ecosystem needs ephemeral
lockfiles: it uses lockfiles, and we parse projects that have only the manifest checked in.

Skip this file entirely if ephemeral lockfile generation is not required for any package
manager in this ecosystem.

## Procedure

1. Write a test for the desired behaviour when a project has no lockfile checked in:
   - We should still get transitive dependencies only present in the lockfile.
   - We should still get subdependencies.
2. Confirm the test fails — we currently only parse the manifest file.
3. Create a nested class to generate a lockfile:
   `{ecosystem}/lib/dependabot/{ecosystem}/dependency_grapher/lockfile_generator.rb`

   This class should:
   1. Accept `dependency_files:` and `credentials:` (and any ecosystem-specific params).
   2. Implement a `generate` method that returns a `Dependabot::DependencyFile`.
   3. Run the ecosystem's native lock command in a temporary directory.
   4. Return a `DependencyFile` object with the generated lockfile content.

   In the main grapher, override `prepare!` to:
   1. Detect when a lockfile is missing.
   2. Call the generator.
   3. Inject the ephemeral lockfile into `dependency_files`.
   4. Set `@ephemeral_lockfile_generated = true`.
   5. Call `super` to proceed with normal parsing.
   6. Rescue errors and call `errored_fetching_subdependencies!`.
4. Verify that the test added in step 1 now passes.
5. Add a test file for the lockfile generator:
   `{ecosystem}/spec/dependabot/{ecosystem}/dependency_grapher/lockfile_generator_spec.rb`
6. Add test coverage for failure modes around ephemeral lockfile generation:
   - Generation failure doesn't crash the grapher.
   - The generated lockfile is not reported as `relevant_dependency_file` — that should still
     point at the real, committed manifest so we don't imply the ephemeral file is something the
     user can inspect or rely on between runs.
7. Emit a warning (via `Dependabot.logger.warn`) encouraging the lockfile to be checked in, and
   noting that transitive dependencies will be in flux between runs as a result (see the
   "Dealing with missing lockfiles" section of
   `common/lib/dependabot/dependency_graphers/README.md`).

## Reference implementation

`python/lib/dependabot/python/dependency_grapher.rb`'s `generate_ephemeral_lockfile!`,
`poetry_project_without_lockfile?`, `committed_poetry_lock` and `emit_missing_lockfile_warning!`
methods, together with `python/lib/dependabot/python/dependency_grapher/lockfile_generator.rb`,
are the full worked example for Poetry projects missing a `poetry.lock`. Note in particular how
`relevant_dependency_file` deliberately excludes the ephemeral lockfile
(`committed_poetry_lock` returns `nil` when `@ephemeral_lockfile_generated` is set) so attribution
still points at `pyproject.toml`.
