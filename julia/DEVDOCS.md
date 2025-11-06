# Julia Dependabot – Developer Guide

This document describes the architecture and current behaviour of the Julia ecosystem support that lives inside Dependabot Core. It is intended for contributors who need to reason about the updater, file fetcher, and the Julia helper.

For user-facing information, read `julia/README.md`.

## Terminology

| File                       | Julia terminology | Dependabot terminology |
|---------------------------|-------------------|------------------------|
| `Project.toml`            | Project file      | Manifest file          |
| `Manifest.toml`           | Manifest          | Lockfile               |

All Ruby and Julia code use Julia’s terminology when logging or producing notices.

## High-Level Architecture

Dependabot keeps the existing Ruby pipeline (file fetcher → parser → updater) and delegates Julia-specific logic to `DependabotHelper.jl`. The two components communicate over JSON-RPC.

```
┌───────────────┐     JSON-RPC      ┌───────────────────────┐
│ Ruby services │ ────────────────► │ DependabotHelper.jl   │
│ (Fetcher,     │ ◄───────────────  │ (Pkg-based operations)│
│ Parser, etc.) │                   └───────────────────────┘
```

Key principles:

1. **Stateless file updaters** – each run operates inside a temporary repo snapshot without shared state.
2. **Per-directory execution** – Dependabot runs the updater for every directory referenced in `dependabot.yml`.
3. **Julia-controlled discovery** – `Pkg.Types.Context` determines which `Project.toml` and `Manifest.toml` apply to the working directory, so we always mirror Julia’s view of the environment.
4. **Relative file identities** – helpers may return paths such as `../Manifest.toml`; Ruby resolves them back to canonical repo paths before building diffs.

## File Discovery (FileFetcher)

`Dependabot::Julia::FileFetcher` shells out to `DependabotHelper.jl.detect_workspace_files`. The helper inspects the requested directory and returns:

- `project_files`: absolute paths to every project file that belongs to the workspace (root + members).
- `manifest_file`: the `Manifest.toml` that Julia would load for those projects.
- `is_workspace`: whether the directory is a workspace root/member.

The Ruby fetcher reads each file from the temporary clone and builds `DependencyFile` objects. When a manifest is shared by multiple projects it sets:

- `associated_manifest_paths` on the manifest file (list of project paths that use it).
- `associated_lockfile_path` on each project file (points to the manifest path).

These metadata fields allow later stages to keep shared lockfiles even when filtering by directory.

## Dependency Parsing

`Dependabot::Julia::FileParser` uses the helper (via `parse_project` and `parse_manifest`) to extract dependency names, requirements, and metadata such as UUIDs. Requirements reference the full repo-relative path to the file that declared them, which lets the updater understand which `Project.toml` must be edited.

## Updating Dependencies

`Dependabot::Julia::FileUpdater` performs three steps for every directory:

1. **Prepare project files**
   - Identify the primary `Project.toml` for the directory.
   - Locate the manifest (same directory or any ancestor).
   - Update compat entries for the requested dependencies in the target project.
   - Update compat entries in sibling projects that share the same manifest. If a project does not declare the dependency in `[deps]`, `[extras]`, or `[weakdeps]`, it is skipped.

2. **Run the Julia helper**
   - Write the updated projects and the manifest into the temporary repo.
   - Call `registry_client.update_manifest` (which invokes `Pkg.add` with the requested versions).
   - The helper returns the new manifest content plus the manifest path relative to the project directory.

3. **Return updated files**
   - Always return the project file for the directory that triggered the updater.
   - Include sibling `Project.toml` files whose compat sections changed.
   - Include the manifest when the helper supplied new content.
   - Resolve relative manifest paths back to the canonical `DependencyFile` so that deduplication works when multiple directories reference the same lockfile.

If the helper raises a resolver error, the updater returns only the updated `Project.toml` and emits a warning notice so the pull request clearly explains why the manifest could not be updated.

## Workspace Handling

Shared lockfiles rely on two behaviours:

1. **Metadata-aware filtering** – both `DependencyChangeBuilder` and `DependencyGroupChangeBatch` keep any file flagged as `shared_across_directories?` or any file whose `associated_lockfile_path` matches the current directory’s manifest, even when that file lives outside the directory being processed.
2. **Sibling compat updates** – before the helper runs, `update_workspace_sibling_projects` rewrites every project that points to the same manifest so the Julia resolver sees consistent requirements across the workspace. This prevents manifests from being regenerated with conflicting compat entries.

## Notices

When manifest updates fail (resolver errors, missing files, etc.) the updater adds a `Dependabot::Notice` with:

- `type`: `julia_manifest_not_updated`
- `title`: which manifest failed
- `description`: the full resolver error
- `show_in_pr` / `show_alert`: both set so end users see the warning

## Error Handling Expectations

- Helper failures raise `Dependabot::SharedHelpers::HelperSubprocessFailed`. Treat these as unknown errors unless the message clearly indicates a resolver issue.
- TOML parsing errors during sibling updates log a warning and default to “dependency is declared” so compat edits continue rather than silently skipping updates.

## Useful Entry Points

- `julia/lib/dependabot/julia/file_fetcher.rb`
- `julia/lib/dependabot/julia/file_parser.rb`
- `julia/lib/dependabot/julia/file_updater.rb`
- `julia/helpers/DependabotHelper.jl/src/DependabotHelper.jl`

These files contain the bulk of the Julia-specific behaviour and are the right places to start when modifying the ecosystem support.
