## `dependabot-apm`

[APM (Agent Package Manager)][apm-repo] support for [`dependabot-core`][core-repo].

APM is a git-based package manager for AI agent context — skills, prompts,
chat modes, instructions and other agent primitives — declared in an `apm.yml`
manifest. Because every dependency resolves to a git ref, Dependabot bumps APM
dependencies the same way it bumps other git-sourced ecosystems (GitHub Actions,
git submodules): by resolving the newest semver tag on the remote and rewriting
the manifest ref.

### What Dependabot updates

Dependabot reads `apm.yml` and proposes updates for **string-shorthand git
dependencies that are pinned to a semver tag**, for example:

```yaml
dependencies:
  apm:
    - microsoft/edge-ai#v1.0.0            # GitHub shorthand pinned to a tag
    - gitlab.com/acme/prompts#v2.1.0      # FQDN shorthand for any git host
    - octo-org/octo-skills/skills/review#v1.4.0  # virtual sub-path within a repo
```

For each such entry Dependabot:

1. Resolves the git remote (`https://<host>/<owner>/<repo>`).
2. Finds the highest semver tag that satisfies the update/cooldown/ignore rules,
   reusing `Dependabot::GitCommitChecker` (the same tag resolution used by the
   GitHub Actions ecosystem).
3. Rewrites only the ref in `apm.yml` (e.g. `#v1.0.0` → `#v1.4.0`), preserving
   the rest of the declaration byte-for-byte.

`devDependencies.apm` entries are updated too and are flagged as non-production
via the `development` dependency group.

### Scope of this version

To keep the first iteration small and reviewable, the following are intentionally
**out of scope** and are ignored (never modified, never erroring):

- **Object-form entries** (`git:`, `registry:`, `id:`, `path:` maps) and `mcp:`
  entries — only the string shorthand is parsed.
- **Branch- and SHA-pinned entries** — these are resolved by APM's own lockfile,
  which Dependabot does not regenerate, so their manifest ref is left untouched.
- **Local path entries** (`./pkg`, `../pkg`, `/pkg`) — not backed by a remote git
  host, so there is nothing to bump.
- **Lockfile writing** — `apm.lock.yaml` is read (to report the package-manager
  version) but not rewritten; APM regenerates it itself after a manifest change.

These are natural follow-ups and can be layered on without changing the manifest
parsing model established here.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell apm
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd apm && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
[apm-repo]: https://github.com/microsoft/apm
