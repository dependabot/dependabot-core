# Implementing manifest grouping (layering)

Load this file when the Gather Requirements step determined the target ecosystem can have
**multiple independent manifests checked into the same directory**, where each one should be
attributed its own snapshot rather than being merged into one (see the "Layered / multi-manifest
directories" section of `common/lib/dependabot/dependency_graphers/README.md` for the underlying
`ManifestGroup`/`manifest_groups` API before starting).

Skip this file entirely if the ecosystem cannot have more than one independent manifest per
directory — the base `Dependabot::DependencyGraphers::Base#manifest_groups` default (one group
spanning the whole directory) already handles that common case correctly.

## Procedure

1. Write a test asserting that a directory containing multiple independent manifests produces
   one snapshot per manifest, each attributed to the correct primary file and containing only
   that manifest's dependencies.
2. Confirm the test fails: `manifest_groups` is not yet overridden, so it defaults to a single
   group for the whole directory.
3. Override `manifest_groups` (returns `T::Array[Dependabot::DependencyGraphers::ManifestGroup]`)
   to:
   - Identify the set of files that act as an independent manifest's "primary" — the file
     dependencies should be attributed to. Prefer a lockfile-like file over a bare manifest where
     both exist for the same layer.
   - For each primary, gather every other file the parser needs to resolve it in isolation
     (paired lockfile/manifest, referenced/included files, shared constraints, etc.), marking
     siblings pulled in only for cross-referencing as support files (`support_file: true`) so
     they never win attribution.
   - Return one `Dependabot::DependencyGraphers::ManifestGroup.new(primary:, files:)` per
     independent manifest.
   - **Fall back to `super` when only one group is found**, so the common single-manifest case
     is unaffected. This is the key defensive pattern — see
     `python/lib/dependabot/python/dependency_grapher.rb`'s `manifest_groups` method for the
     exact shape:

     ```ruby
     sig { override.returns(T::Array[Dependabot::DependencyGraphers::ManifestGroup]) }
     def manifest_groups
       return super unless supports_layering?

       groups = SomeLayeringHelper.new(dependency_files: dependency_files).groups
       return super if groups.length < 2

       groups
     end
     ```
4. Verify the test now passes. `manifest_group_snapshots` (inherited from `Base`) resolves each
   group independently via a scoped grapher and propagates any subdependency-fetching errors back
   up automatically — you do not need to implement that part yourself.
5. Add test coverage for edge cases:
   - A directory with only one manifest still resolves via the base single-group path.
   - Cross-referenced/shared support files are included in every group that needs them but don't
     themselves win attribution.
   - Files that don't belong to any recognised manifest are excluded from every group.
   - If the ecosystem also allows other, unrelated manifest types to share the same directory
     (e.g. Python's `setup.py`/`pyproject.toml` sharing a directory with layered requirements
     files), make sure those get their own self-attributed group too, rather than being dropped —
     see `non_requirements_manifest_groups` in `python/lib/dependabot/python/dependency_grapher.rb`
     for the pattern.

## Reference implementation

`python/lib/dependabot/python/dependency_grapher/requirements_layers.rb` is the full worked
example: it splits a directory of pip/pip-compile requirements files (e.g. `base-requirements.txt`,
`test-requirements.txt`, `dev-requirements.in`) into one group per "layer", resolving `-r`/`-c`
cross-references transitively so each layer can be parsed in isolation.
