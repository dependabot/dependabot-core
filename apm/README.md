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
dependencies that are pinned to a semver tag, a commit SHA or a branch**. Tag
pins are the most common, for example:

```yaml
dependencies:
  apm:
    - microsoft/edge-ai#v1.0.0            # GitHub shorthand pinned to a tag
    - gitlab.com/acme/prompts#v2.1.0      # FQDN shorthand for any git host
    - octo-org/octo-skills/skills/review#v1.4.0  # virtual sub-path within a repo
    - acme.ghe.com/org/repo/skills/review#v1.0.0 # virtual sub-path on a GHE Cloud host
```

Virtual sub-paths (`repo/skills/review`) are resolved on GitHub-family hosts —
`github.com` and GitHub Enterprise Cloud data-residency hosts (`*.ghe.com`),
which APM also treats as GitHub. On other hosts the whole path is treated as the
repository; virtual packages on self-hosted GHES (reachable only via an
arbitrary configured `GITHUB_HOST`) are a follow-up.

For each such entry Dependabot:

1. Resolves the git remote (`https://<host>/<owner>/<repo>`).
2. Finds the highest semver tag that satisfies the update/cooldown/ignore rules,
   reusing `Dependabot::GitCommitChecker` (the same tag resolution used by the
   GitHub Actions ecosystem).
3. Rewrites only the ref in `apm.yml` (e.g. `#v1.0.0` → `#v1.4.0`), preserving
   the rest of the declaration byte-for-byte.

Both plain `v1.4.0` / `1.4.0` tags and APM's package-scoped tags —
`review-v1.4.0`, `review--v1.4.0` and `review_v1.4.0`, where the prefix is the
package's own name (the repository name, or the final virtual-path component) —
are recognised, so a monorepo that tags each package independently is updated
correctly. Build metadata (`+build.5`) is preserved and, per SemVer, ignored for
precedence; equal-precedence tags break ties on the full tag string, so tag
resolution stays deterministic regardless of the order the remote advertises
them.

#### Commit SHA pins

Full 40-character SHA pins (`owner/repo#<sha>`) follow `apm update`: the pin
moves to the commit of the repository's latest **annotated**, non-prerelease
semver release tag (in any of the tag forms above), and the entry is annotated
with that tag, replacing any comment already on its line:

```yaml
    - microsoft/edge-ai#0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e # v1.4.0
```

Lightweight tags and branches are never used as a SHA pin's target. Unlike
`apm update`, Dependabot never moves a SHA pin that is itself a tagged release
to a lower version. Abbreviated SHAs are skipped, as APM leaves them unchanged.
Ignore conditions and cooldown apply as for tag pins; security advisories do
not, as a SHA has no version to compare.

#### Branch pins

A branch pin (`owner/repo#main`, or any other non-semver ref such as a floating
`v1` tag) is updated to the branch's current head commit. The manifest still
names the branch, so only `apm.lock.yaml` changes. A branch pin is only updated
when the lockfile records the commit its branch was resolved to; without a
lockfile there is no current commit to compare against, so it is skipped.
Cooldown and security advisories don't apply to branch pins.

When a package is declared with several kinds of pin, only its most specific
declarations (tag, then SHA, then branch) are updated.

#### Lockfile regeneration

When the repository has an `apm.lock.yaml`, Dependabot regenerates it with the
APM CLI's `apm lock`, which resolves the updated manifest without deploying any
package files. APM only re-resolves the entries whose manifest ref changed, so
every other entry keeps its locked commit. A branch pin's lock entry is first
moved to the branch's new head commit (dropping its now stale `content_hash`)
for APM to verify and re-hash. APM rewrites the whole file, so its
`apm_version` also changes to the version of the CLI Dependabot runs. A missing
lockfile is never created.

The APM CLI is installed as a native helper from the official
[release binaries][apm-releases] (see `helpers/build`), pinned to a version and
verified against its SHA-256 checksum.

`devDependencies.apm` entries are updated too and are flagged as non-production
via the `development` dependency group.

### Scope of this version

To keep the first iteration small and reviewable, the following are intentionally
**out of scope** and are ignored (never modified, never erroring):

- **Object-form entries** (`git:`, `registry:`, `id:`, `path:` maps) and `mcp:`
  entries — only the string shorthand is parsed.
- **Unpinned entries** (`owner/repo` with no `#ref`) — these track the default
  branch and are left to `apm update`.
- **Local path entries** (`./pkg`, `../pkg`, `/pkg`) — not backed by a remote git
  host, so there is nothing to bump.
- **Azure DevOps hosts** (`dev.azure.com`, `ssh.dev.azure.com` and legacy
  `*.visualstudio.com`) — APM resolves these to `org/project/_git/repo` clone
  URLs, a structure this version's generic `host/owner/repo` builder cannot
  construct, so ADO entries are skipped rather than resolved to a wrong remote.
  Native `_git` clone-URL support is a follow-up.
- **`http://` and `git://` clone URLs** — Dependabot enumerates tags over HTTPS,
  so an `https://` or `ssh://`/SCP explicit URL is resolved (SSH over HTTPS on the
  same host, keeping any `https://` port). A plain `http://` or `git://` URL names
  a different endpoint (a distinct port, and for `http` an unencrypted service),
  so it is skipped rather than silently rewritten to `https://`.
- **Block-scalar and escaped string entries** — a shorthand written as a YAML
  block scalar (folded `>` / literal `|`) or as a quoted scalar that relies on
  escape sequences (e.g. `"owner/repo\x23v1.0.0"`) decodes to text that is not a
  contiguous slice of the manifest source, so its ref cannot be rewritten in
  place. These uncommon spellings are skipped rather than producing a failing
  update; write the shorthand as a plain or simply-quoted scalar
  (`owner/repo#v1.0.0`) to have it updated.

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
[apm-releases]: https://github.com/microsoft/apm/releases
