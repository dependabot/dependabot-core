## `dependabot-nimble`

Nimble support for [`dependabot-core`][core-repo]. **Beta**: it only runs when beta ecosystems are enabled.

[Nimble](https://github.com/nim-lang/nimble) is the package manager of the [Nim](https://nim-lang.org) language.

### What it does

- **Fetches** the `<name>.nimble` file in the directory.
- **Parses** the packages named by `requires` and `taskRequires` calls, with their version ranges
  (`>= 1.2`, `== 1.2`, `^= 1.2`, `~= 1.2`, `>= 1.0 & < 2.0`, or no range). `requires "nim >= 2.0"` is the
  compiler, not a dependency, and is left alone, as are packages given as a URL or a git ref (`#head`).
- **Checks for updates** by finding the package in the [Nimble package index][index], which gives the git
  repository, and listing the version tags of that repository. Cooldown uses the date of each tag's commit.
- **Updates** the version in the `requires` string, in place, keeping the rest of the file as it is. The lower
  bound moves to the latest version; an upper bound that excludes the latest version leaves the range alone.

### What it does not do (yet)

- `nimble.lock` is not read or updated. A project that keeps a lock file has to refresh it after the update.
- Packages hosted with Mercurial and private package indexes are not supported.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell nimble
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd nimble && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core
[index]: https://github.com/nim-lang/packages

### Implementation Status

See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for the process.

#### Required Classes
- [x] FileFetcher
- [x] FileParser
- [x] UpdateChecker
- [x] FileUpdater

#### Optional Classes
- [x] MetadataFinder
- [x] Version
- [x] Requirement
- [ ] PackageManager and language classes (no native helper is needed)

#### Features
- [x] Cooldown
- [x] Security updates (`lowest_security_fix_version`)
- [ ] Lock file (`nimble.lock`)
- [ ] Smoke tests ([dependabot/smoke-tests](https://github.com/dependabot/smoke-tests))
