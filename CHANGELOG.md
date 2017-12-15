## v0.39.5, 15 December 2017

- PHP: More sensitive handling of multi-version library requirements

## v0.39.4, 15 December 2017

- PHP: Make UpdateChecker work for dev dependencies

## v0.39.3, 15 December 2017

- PHP: Parse development dependencies properly

## v0.39.2, 15 December 2017

- PHP: Strip leading `v` from versions in packagist API response

## v0.39.1, 14 December 2017

- PHP: Only treat repos as libraries if they declare "library" as their type

## v0.39.0, 14 December 2017

- PHP: Support PHP libraries

## v0.38.8, 14 December 2017

- PHP: Raise clear error when Composer is out of memory

## v0.38.7, 14 December 2017

- PHP: Treat last error correctly (as an array)

## v0.38.6, 14 December 2017

- PHP: Try and add some memory that will be freed on error

## v0.38.5, 14 December 2017

- PHP: Handle shutdown errors

## v0.38.4, 14 December 2017

- PHP: Throw out of memory errors

## v0.38.3, 13 December 2017

- Python: Preserve original host environment markers in Pipfile.lock

## v0.38.2, 13 December 2017

- Python: Handle * version strings in UpdateChecker

## v0.38.1, 13 December 2017

- Python: Make Pipfile an explicit dependency

## v0.38.0, 13 December 2017

- Python: Add experimental Pipfile support

## v0.37.2, 13 December 2017

- Python: Handle multi-line requirements, and preserve previous whitespace

## v0.37.1, 13 December 2017

- Python: Handle custom algorithms for hashes

## v0.37.0, 13 December 2017

- Python: update hashes in requirements.txt file if present
- BREAKING: Install Python requirements from a requirements.txt

## v0.36.30, 12 December 2017

- Allow `custom_label` to be passed to PullRequestCreator

## v0.36.29, 12 December 2017

- Use existing dependencies label if present

## v0.36.28, 12 December 2017

- PHP: Handle dependendencies with capitals (especially PEAR dependencies)

## v0.36.27, 12 December 2017

- PHP: Handle packagist returning packages for a different name

## v0.36.26, 12 December 2017

- PHP: Downcase dependency names when constructing packagist URLs

## v0.36.25, 12 December 2017

- Python: Only fetch files that end in `.txt` from any requirements folder

## v0.36.24, 12 December 2017

- Python: Support alternative names / locations for requirements.txt files

## v0.36.23, 11 December 2017

- PHP: Handle resolvability errors (silence them)

## v0.36.22, 11 December 2017

- JS: Handle unparseable package-lock.json files
- JS: Handle JSON parser errors in non-standard registries

## v0.36.21, 9 December 2017

- PHP: Store details of source URL during file parsing
- PHP: Pull source URL details from dependency in MetadataFinder, if present

## v0.36.20, 8 December 2017

- PHP: Refactored and cleaned up PHP code (thanks @nesl247)

## v0.36.19, 8 December 2017

- PHP: Only use github token if provided one

## v0.36.18, 8 December 2017

- PHP: Actually use auth credentials

## v0.36.17, 8 December 2017

- PHP: Fix for SSH URLs

## v0.36.16, 8 December 2017

- PHP: Handle SSH URLs in FileUpdater

## v0.36.15, 8 December 2017

- Ruby: More conservative full-unlocking. Reduces number of dependencies
  unlocked and/or number of iterations to discover unlocking is impossible.

## v0.36.14, 8 December 2017

- Prepare composer.json files in Ruby to avoid re-writing JSON

## v0.36.13, 8 December 2017

- Include semantic commit message prefix only if repo uses them

## v0.36.12, 8 December 2017

- Don't submit empty author details to GitHub

## v0.36.11, 8 December 2017

- Allow author details to be passed to PullRequestCreator and PullRequestUpdater

## v0.36.10, 8 December 2017

- PHP: Handle 404s from packagist

## v0.36.9, 7 December 2017

- PHP: Handle repo not reachable errors

## v0.36.8, 7 December 2017

- PHP: Pass GitHub access token to PHP helpers

## v0.36.7, 7 December 2017

- PHP: Add back platform override now it's properly specced

## v0.36.6, 7 December 2017

- PHP: Update composer.json files in Ruby, to avoid changing their formatting
- PHP: Better requirements updater in UpdateCheckers

## v0.36.5, 7 December 2017

- JS: Better npm update_checker errors
- JS: prune git dependencies out during file parsing

## v0.36.4, 7 December 2017

- PHP: Stop setting prefer-stable explicitly
- PHP: Temporarily disable updates where a PHP version is specified

## v0.36.3, 7 December 2017

- PHP: Don't check platform requirements during updates

## v0.36.2, 6 December 2017

- PHP: Try setting a much higher memory limit for composer

## v0.36.1, 6 December 2017

- JS: Give registries a break before retrying if they return bad JSON

## v0.36.0, 5 December 2017

- Stop supporting npm and yarn as package managers (in favour of npm_and_yarn)

## v0.35.15, 5 December 2017

- JS: Combine Yarn and npm package managers into NpmAndYarn

## v0.35.14, 5 December 2017

- JS: Check for yanked versions in UpdateChecker

## v0.35.13, 5 December 2017

- JS: Fix UpdateChecker retrying

## v0.35.12, 4 December 2017

- Ruby: handle gemspecs that dup a version constant

## v0.35.11, 4 December 2017

- JS: retry transitory JSON parsing failures

## v0.35.10, 4 December 2017

- JS: raise DependencyFileNotResolvable when no satisfiable version can be found
  for an npm dep

## v0.35.9, 3 December 2017

- JS: Handle thorny single requirements

## v0.35.8, 3 December 2017

- JS: Handle JS requirements in branch names
- JS: Handle library requirements differently to application requirements

## v0.35.7, 3 December 2017

- JS: Return pre-release versions in UpdateChecker if one is currently in use

## v0.35.6, 3 December 2017

- JS: raise DependencyFileNotResolvable when no satisfiable version can be found
  for a Yarn dep

## v0.35.5, 2 December 2017

- JS: Fix updated_files_regex for Yarn
- JS: handle updates without a lockfile in FileUpdater
- JS: support repos without a lockfile in npm parser, and spec support in UpdateChecker
- JS: support repos without a package-lock.json in npm FileFetcher

## v0.35.4, 1 December 2017

- Ruby: Fix bug in gemspec sanitizing

## v0.35.3, 1 December 2017

- Implement equality operator for DependencyFile

## v0.35.2, 1 December 2017

- Ruby: More robust gemspec sanitizing

## v0.35.1, 1 December 2017

- JS: Ignore transitory errors from custom registries

## v0.35.0, 30 November 2017

- JS: Perform package.json update in Ruby (and avoid changing package.json
  format)

## v0.34.20, 30 November 2017

- Ruby: Handle repos with a gemspec and a Gemfile that doesn't import it

## v0.34.19, 30 November 2017

- JS: Preserve protocol for private registries

## v0.34.18, 30 November 2017

- JS: Handle private registries that don't use https

## v0.34.17, 30 November 2017

- JS: Better parsing of private registry URLs

## v0.34.16, 29 November 2017

- JS: Include private dependencies when parsing npm package-lock.json

## v0.34.15, 29 November 2017

- JS: Pull credentials from npmrc file, if present

## v0.34.14, 29 November 2017

- JS: Raise a PrivateSourceNotReachable error for missing private details

## v0.34.13, 29 November 2017

- JS: Pass credentials for non-npm registries to file updater
- JS: use custom registries (with credentials) in UpdateChecker and
  MetadataFinder
- JS: Fetch .npmrc files
- JS: Use sanitized .npmrc files in FileUpdater

## v0.34.12, 29 November 2017

- JS: Add basic support for private npm packages

## v0.34.11, 28 November 2017

- Ruby: Handle Bundler::Fetcher::CertificateFailureError errors

## v0.34.10, 27 November 2017

- Ruby: Roll back regression in ForceUpdater

## v0.34.9, 27 November 2017

- Ruby: More conservative ForceUpdater (traverse requirement trees from top)

## v0.34.8, 27 November 2017

- Ruby: Make ForceUpdater more conservative about what it unlocks

## v0.34.7, 27 November 2017

- Ruby: Fix for custom-sourced peer dependencies in ForceUpdater

## v0.34.6, 27 November 2017

- Make dependency we're force updating the first in the returned array

## v0.34.5, 27 November 2017

- Minor improvement to PR text
- Make new_dependencies_to_unlock_from unique

## v0.34.4, 24 November 2017

- Better pull request text for multi-dependency PRs

## v0.34.3, 24 November 2017

- Fix for PullRequestCreator metadata links with multiple dependencies

## v0.34.2, 23 November 2017

- Fix another bug in PullRequestCreator

## v0.34.1, 23 November 2017

- Fix bug in PullRequestCreator which occurs when a source_url can't be found

## v0.34.0, 23 November 2017

- BREAKING: PullRequestCreator now takes an array of `dependencies`

## v0.33.0, 23 November 2017

- BREAKING: FileUpdaters now take an array of `dependencies`, not a `dependency`

## v0.32.0, 23 November 2017

- BREAKING: Return an array of dependencies from
  `UpdateCheckers::Base#updated_dependencies`

## v0.31.0, 22 November 2017

- BREAKING: Split `UpdateCheckers::Base#needs_update?` method into `up_to_date?`
  and `can_update?` methods

## v0.30.6, 21 November 2017

- Python: More robust setup.py error handling

## v0.30.5, 21 November 2017

- Python: Further fix for UpdateChecker prerelease handling

## v0.30.4, 21 November 2017

- Python: Better pre-release handling in UpdateChecker

## v0.30.3, 21 November 2017

- Ruby: Ignore path gemspecs that are behind falsey conditional

## v0.30.2, 21 November 2017

- PHP: Silence out-of-memory errors

## v0.30.1, 21 November 2017

- Ruby: Handle GitHub sources when checking for inaccessible dependencies

## v0.30.0, 20 November 2017

- Pass a source hash to FileFetchers, rather than a repo name
- Pass a credentials hash to FileFetchers, rather than a GitHub client

## v0.29.1, 20 November 2017

- JS: Pass full requirements to Yarn updater.js to circumvent Yarn bug

## v0.29.0, 20 November 2017

- JS: Ignore node manifest engine constraints
- Make MetadataFinders provider agnostic (i.e., don't treat GitHub differently)

## v0.28.9, 20 November 2017

- Ruby: Respect user's spacing between specifier and version

## v0.28.8, 20 November 2017

- Ruby: Handle Gemfiles with path sources but no Gemfile.lock

## v0.28.7, 17 November 2017

- Start commit messages with "chore(dependencies): "

## v0.28.6, 17 November 2017

- JS: FileUpdaters::JavaScript::Yarn.updated_files_regex now includes
  package.json files that aren't at the top level

## v0.28.5, 17 November 2017

- JS: Fix Yarn workspace handling in FileUpdater

## v0.28.4, 17 November 2017

- Python: Extract dependencies from `setup_requires` and `extras_require`
  (thanks @tristan0x)

## v0.28.3, 17 November 2017

- JS: Handle wildcards in package.json

## v0.28.2, 17 November 2017

- JS: Ignore empty files in FileUpdater

## v0.28.1, 17 November 2017

- JS: Handle workspace names more robustly

## v0.28.0, 16 November 2017

- JS: Support Yarn workspaces

## v0.27.17, 16 November 2017

- JS: Fetch and parse workspace package.json files (awaiting FileUpdater change)

## v0.27.16, 15 November 2017

- MetadataFinders: Strip out # characters from source URLs

## v0.27.15, 15 November 2017

- JS: Sanitize any variables in a package.json before parsing/updating

## v0.27.14, 13 November 2017

- Ruby: handle yet more private gem repo failure cases

## v0.27.13, 13 November 2017

- Ruby: handle more private gem repo failure cases

## v0.27.12, 13 November 2017

- Python: Ignore errors when parsing setup.py (temporary)

## v0.27.11, 13 November 2017

- Handle bad GitHub source data links in GitCommitChecker
- Python: Handle setup.py calls better

## v0.27.10, 12 November 2017

- Case insensitive Ruby version replacement

## v0.27.9, 11 November 2017

- Add support for passing a target branch to create PRs against

## v0.27.8, 11 November 2017

- Python: more setup.py handling

## v0.27.7, 10 November 2017

- Fix typo

## v0.27.6, 10 November 2017

- Handle Python setup.py files that use codec.open

## v0.27.5, 10 November 2017

- Attempt to handle setup.py file that include an "open" line

## v0.27.4, 10 November 2017

- Sanitize Python requirement branch names

## v0.27.3, 10 November 2017

- Handle Python range requirements

## v0.27.2, 10 November 2017

- Handle Python requirements that specify a prefix-match

## v0.27.1, 10 November 2017

- Handle setup.py file that include a print statement
- Retry Docker timeouts

## v0.27.0, 09 November 2017

- Add support for Python libraries (i.e., repos with a setup.py)

## v0.26.0, 09 November 2017

- Make repo a required argument to FileParsers

## v0.25.8, 09 November 2017

- Ignore custom names for submodule dependencies

## v0.25.7, 09 November 2017

- Handle relative URLs for git submodules

## v0.25.6, 08 November 2017

- Handle missing Ruby private dependencies

## v0.25.5, 08 November 2017

- Allow Rubygems 2.6.13 for now (since Heroku uses it)

## v0.25.4, 07 November 2017

- Add homepage links for Python and JavaScript
- Remove Rubygems monkeypatch in favour of required rubygems version

## v0.25.3, 31 October 2017

- Require Bundler 1.16.0

## v0.25.2, 30 October 2017

- Link to Ruby dependency homepage if source code can't be found
- Refactor GitHub specific logic out of PullRequestCreator

## v0.25.1, 28 October 2017

- Add npm require line to FileUpdaters

## v0.25.0, 28 October 2017

- Alpha support for npm

## v0.24.9, 25 October 2017

- Treat Ruby dependencies which explicitly specify the default source the same
  as ones that do so implicitly during file parsing
- Pick up files called `release` when looking for changelogs

## v0.24.8, 24 October 2017

- Handle date-like versions in Dockerfile

## v0.24.7, 24 October 2017

- Only update Dockerfile version to pre-release if currently using one

## v0.24.6, 24 October 2017

- Better handling of Python dependencies that specify a minor version

## v0.24.5, 24 October 2017

- Set private repo config properly in Ruby::Bundler::UpdateCheckers

## v0.24.4, 21 October 2017

- Add support for Dockerfiles versions with a suffix (e.g., 2.4.2-slim)

## v0.24.3, 20 October 2017

- Look up Python URLs from PyPI description if necessary

## v0.24.2, 18 October 2017

- Handle absolute paths in Ruby Gemfiles

## v0.24.1, 17 October 2017

- Add temporary ignore for private npm organisation hosted dependencies in
  UpdateChecker. Once we support passing credentials we'll be able to bump
  these, but for now we just supress them

## v0.24.0, 17 October 2017

- Support private docker registries that use digests

## v0.23.3, 16 October 2017

- Link to changelog for Ruby git dependencies where the ref is bumped

## v0.23.2, 13 October 2017

- Support updating docker images hosted on a private registry

## v0.23.1, 13 October 2017

- Docker registry regex now excludes trailing slash
- Require private Docker registries to specify a port

## v0.23.0, 13 October 2017

- BREAKING: Require an array of `credentials` to be passed for FileUpdaters and
  UpdateCheckers, rather than a `github_access_token`.

## v0.22.8, 12 October 2017

- Add support for Dockerfiles that specify a digest
- Spec that docker support works when multiple FROM lines are specified
- Bump yarn-lib from 1.1.0 to 1.2.0

## v0.22.7, 10 October 2017

- Use monkeypatch for CVE-2017-0903 rather than requiring specific Rubygems
  version (since Heroku doesn't get support 2.6.14)

## v0.22.6, 10 October 2017

- Filter out private JS dependencies during parsing

## v0.22.5, 10 October 2017

- Require Rubygems version 2.6.14 to ensure safety from CVE-2017-0903

## v0.22.4, 09 October 2017

- Check new git version is resolvable when updating Ruby git tags

## v0.22.3, 09 October 2017

- Handle git:// URLs in GitCommitChecker

## v0.22.2, 09 October 2017

- Raise a PrivateSourceNotReachable error for private Docker registries

## v0.22.1, 08 October 2017

- Fix bad require line for FileFetchers

## v0.22.0, 08 October 2017

- Add support of Dockerfiles

## v0.21.3, 07 October 2017

- Refactor GitCommitChecker and use it for update-checking submodules

## v0.21.2, 07 October 2017

- Better pull request versions when upgrading a tag

## v0.21.1, 07 October 2017

- Handle non-GitHub URLs in GitCommitChecker#local_tag_for_version
- Robust handling of quote characters for Ruby::Bundler::GitPinReplacer
- Use GitCommitChecker for fetching the latest commit on a branch (speedup)

## v0.21.0, 06 October 2017

- Support bumping Ruby git dependencies that are tagged to a version-like tag

## v0.20.15, 06 October 2017

- Don't sanitize python requirement names during parsing. Was causing errors
  at the FileUpdater stage (since the name no-longer matched the declaration).

## v0.20.14, 05 October 2017

- Add error handling for ChildGemfileFinder path evaluation

## v0.20.13, 04 October 2017

- Add support for eval_gemfile to Ruby

## v0.20.12, 04 October 2017

- Use Excon automatic retries when making get requests. Should considerably
  reduce timeout errors from NPM, PyPI, etc.

## v0.20.11, 04 October 2017

- More robust handling of Ruby dependencies with a git source (handle errors
  that occur from attempting to remove the git source)

## v0.20.10, 04 October 2017

- Don't update Ruby gemfiles which specify their version using a function

## v0.20.9, 03 October 2017

- Change: Transition Ruby git sources to Rubygems releases when a branch is
  specified and its head is behind the release

## v0.20.8, 02 October 2017

- Change: Consider possible changelog names in order
- Fix: Only consider files when looking for a changelog

## v0.20.7, 02 October 2017

- Refactor: Split up Ruby FileParser. Should have no effect on public APIs

## v0.20.6, 01 October 2017

- Handle relative requirements in cascaded Python requirement files properly

## v0.20.5, 01 October 2017

- Fetch cascading Python requirement files that aren't specified with a
  leading `./`

## v0.20.4, 29 September 2017

- Fix: Don't error when calculating MetadataFinder commits_url for Ruby git
  dependencies with an unknown source

## v0.20.3, 29 September 2017

- Change: Clearer PR wording for git references switching to releases

## v0.20.2, 29 September 2017

- Fix: Add temporary workaround for ::Bundler::Dsl::VALID_KEYS not being defined

## v0.20.1, 29 September 2017

- Fix: Remove unnecessary require from PullRequestCreator

## v0.20.0, 29 September 2017

- Feature: Support transitioning Ruby git sources to Rubygems releases

## v0.19.12, 28 September 2017

- Change: Use naked version when specifying a Ruby version exactly in Gemfile

## v0.19.11, 28 September 2017

- Fix: Fix metadata handler for non-GitHub Ruby git sources
- Fix: Handle function calls as gem versions in the Ruby FilePreparer
- Fix: Handle string interpolation in Ruby FileUpdater

## v0.19.10, 27 September 2017

- Refactor: Switch to AST parser for updating Ruby requirements in FileUpdater
- Refactor: Remove Gemnasium dependency (we now use Parser for all Ruby parsing)

## v0.19.9, 27 September 2017

- Refactor: Extract Ruby UpdateChecker file preparation into separate class
- Refactor: Switch to AST parser for updating Ruby requirements in UpdateChecker

## v0.19.8, 26 September 2017

- Add short-circuit fetch_latest_version code for Ruby git dependencies
- Refactor UpdateCheckers::Ruby::Bundler (should have no impact on logic)

## v0.19.7, 25 September 2017

- Supress Ruby VersionConflict exceptions caused by an update to a git
  dependency (since the version conflict is only caused by the attempted
  update, not by anything wrong with the underlying Gemfile/Gemfile.lock)

## v0.19.6, 25 September 2017

- Better commit URLs links for Ruby dependencies that specify a git source

## v0.19.5, 25 September 2017

- Handle non-existant git branches for Ruby dependencies

## v0.19.4, 23 September 2017

- Add support for upgrading Ruby dependencies that specify a git source

## v0.19.3, 22 September 2017

- Yarn 1.0 support
- Improve Python parser so it handles paths with spaces

## v0.19.2, 22 September 2017

- Specify required Bundler version is >= 1.16.0.pre
- Set git reference as version for Ruby git dependencies (groundwork for
  updating Ruby dependencies that specify a git source)

## v0.19.1, 21 September 2017

- Better support for Python constraints files, and a general refactor of
  Python support

## v0.19.0, 20 September 2017

- BREAKING: Add source key to dependency requirement attribute, as a
  required key
- Use requirement source key to ensure default metadata is only fetched
  when appropriate

## v0.18.12, 19 September 2017

- Raise GitDependencyReferenceNotFound errors during Ruby update checking

## v0.18.11, 15 September 2017

- Don't create Gemfile requirement for gemspec dependencies
- Don't update Gemfile content during update check if dependency isn't found
  there

## v0.18.10, 12 September 2017

- Handle custom names for submodules, and URLs without a .git suffix

## v0.18.9, 11 September 2017

- Fall back to latest_resolvable_version if PHP latest_version shortcut fails

## v0.18.8, 11 September 2017

- Better error messaging for unreachable submodules

## v0.18.7, 11 September 2017

- Fix typo in submodule checking URL

## v0.18.6, 11 September 2017

- Convert git URLs to https in submodule parser

## v0.18.5, 11 September 2017

- Use correct git internals URL for authorization checking in Ruby UpdateChecker
- Use git internal transfer protocol when fetching latest version of submodules

## v0.18.4, 10 September 2017

- Add shortcut for PHP update_checker version check

## v0.18.3, 9 September 2017

- Handle development dependencies for PHP projects
- Add Dependabot::DependencyFileNotParseable error
- Increase memory limit for PHP

## v0.18.2, 9 September 2017

- Better titles and branch names for git submodule PRs
- Better commit links for git submodule PRs

## v0.18.1, 8 September 2017

- Handle submodule URLs that resolve to a 404

## v0.18.0, 8 September 2017

- Add support for git submodules

## v0.17.3, 7 September 2017

- Handle non-utf-8 characters in Gemfile resolution error messages

## v0.17.2, 7 September 2017

- Handle branch deletion during update flow (return nil, rather than erroring)
- Manually set Bundler root during file update (thanks @gotjosh)

## v0.17.1, 7 September 2017

- Use Bundler 1.16.0 (pre-release 2)

## v0.17.0, 5 September 2017

- Use Bundler 1.16.0 (pre-release 1)

## v0.16.17, 5 September 2017

- Fix HTTP request that checks whether a git dependency is accessible

## v0.16.16, 3 September 2017

- Handle Ruby Gemfile requirements with multiple components

## v0.16.15, 2 September 2017

- Handle non-numberic Python versions better (ignore them instead of erroring)

## v0.16.14, 1 September 2017

- Don't include pre-releases in Python latest_version (unless on one)

## v0.16.13, 30 August 2017

- Use rubygems changelog URL when available
- Fetch more tags when finding metadata

## v0.16.12, 29 August 2017

- Handle path-based JS dependencies

## v0.16.11, 25 August 2017

- Handle optional JS dependencies

## v0.16.10, 25 August 2017

- Raise a DependencyFileNotResolvable error if the lockfile is missing a gem
- Handle inaccessible git dependencies that resolve to a redirect

## v0.16.9, 25 August 2017

- Simpler, better Gemfile sanitizing in UpdateCheckers::Ruby

## v0.16.8, 24 August 2017

- Add dependencies label in separate API call

## v0.16.7, 24 August 2017

- Create "dependencies" label during PR creation, if it doesn't already exist

## v0.16.6, 24 August 2017

- Add "dependencies" label to pull requests

## v0.16.5, 24 August 2017

- Prune out Ruby specs from the wrong platform during parsing

## v0.16.4, 23 August 2017

- Compare Ruby development requirements to the latest resolvable version

## v0.16.3, 23 August 2017

- More robust check on whether Ruby Gemspec file needs updating

## v0.16.2, 23 August 2017

- Handle Ruby case of Gemfile not importing its gemspec
- Exclude platform-specific dependencies from Ruby FileParser
- Handle pre-release version in requirement updates
- Minor PR wording improvement

## v0.16.1, 22 August 2017

- Better key symbolizing on Dependency (handle ActionController::Params)

## v0.16.0, 22 August 2017

- BREAKING: use arrays of hashes for `Dependency#requirements` and
  `Dependency#previous_requirements`, so we can store metadata about each
  requirement (e.g., which file it came from).

## v0.15.8, 22 August 2017

- Allow Ruby updates for repos which only contain a Gemfile (or where the
  dependency only appears in the Gemfile)

## v0.15.7, 21 August 2017

- Link to release notes index when more appropriate than specific release
- Handle gemspecs that bracket their dependencies

## v0.15.6, 19 August 2017

- Check all requirements are binding when creating updated requirements
- Better pull request text when updating libraries

## v0.15.5, 18 August 2017

- Patch Bundler to use HTTPS instead of SSH for git sources hosted on GitHub

## v0.15.4, 16 August 2017

- Use updated gemspec content when calculating new lockfile version (Ruby)
- Handle dev dependencies differently for gemspecs

## v0.15.3, 16 August 2017

- Always use latest_version if updating a gemspec dependency
- Handle Ruby file updates where a non-Gemfile dependency has been updated in
  the lockfile

## v0.15.2, 16 August 2017

- Clearer error message for FileFetchers::Ruby::Bundler

## v0.15.1, 16 August 2017

- Handle Gemfile and gemspec case where a gem only appears in the later

## v0.15.0, 16 August 2017

- Add `.updated_files_regex` to all FileUpdaters
- Remove `.required_files` from all FileFetchers
- Add `.required_files_in?` and `required_files_message` to all FileFetchers
- Remove all `Ruby::Gemspec` classes entirely. Gem bumping behaviour now
  handled in `Ruby::Bundler`

## v0.14.6, 15 August 2017

- Ensure blank strings aren't provided as arguments to Dependency.new

## v0.14.5, 15 August 2017

- Big refactor of `bundler` and `gemspec` flows to almost combine them.
  Hopefully no impact on functionality. Releasing to test in the wild.

## v0.14.4, 15 August 2017

- Update bundler FileParser to handle gemspecs
- Update equality matchers to ranges in UpdateCheckers::Ruby::Gemspec

## v0.14.3, 15 August 2017

- Parse JavaScript files which only have dev dependencies

## v0.14.2, 14 August 2017

- Fix UpdateCheckers::Ruby::Gemspec (oops)

## v0.14.1, 14 August 2017

- Fix: convert version to string before splitting in UpdateChecker

## v0.14.0, 14 August 2017

- Add `requirement` and `previous_requirement` attributes to `Dependency`

## v0.13.4, 14 August 2017

- Better FileUpdaters::Gemspec regex (catch add_runtime_dependency declarations)
- Extend aggressive gemspec sanitization to Bundler

## v0.13.3, 13 August 2017

- More aggressive gemspec sanitizing

## v0.13.2, 13 August 2017

- Use original quote character when updating Ruby gemspecs
- Clearer text for library pull requests

## v0.13.1, 13 August 2017

- More robust gemspec declaration regex

## v0.13.0, 13 August 2017

- BREAKING: Return strings from Dependency#version, not Gem::Version objects
- FEATURE: Add support for Ruby libraries (i.e., gems)

## v0.12.8, 12 August 2017

- Don't add RUBY VERSION to the Gemfile.lock if it wasn't previously present

## v0.12.7, 12 August 2017

- Sanitize path-based gemspecs to remove fine requirements

## v0.12.6, 12 August 2017

- Handle Ruby indexes that only implement the old Rubygems index

## v0.12.5, 11 August 2017

- Raise helpful message for Ruby private sources without auth details

## v0.12.4, 10 August 2017

- Serve a DependencyFileNotResolvable error for bad git branches

## v0.12.3, 10 August 2017

- Handle requirement.txt files that have cascading requirements

## v0.12.2, 8 August 2017

- Handle requirement.txt files that have path-based dependencies

## v0.12.1, 5 August 2017

- Handle 404s from Rubygems in UpdateChecker
- Skip PHP dependencies with non-numberic versions during file parsing

## v0.12.0, 4 August 2017

- BREAKING: Return `Gem::Version` objects from Dependency#version, not strings

## v0.11.2, 23 July 2017

- Ignore Python packages which can't be found at PyPI

## v0.11.1, 17 July 2017

- Handle deleted branches in PullRequestUpdater

## v0.11.0, 12 July 2017

- Handle Gemfiles that load in a .ruby-version file
- Move Python parser code into Python helper

## v0.10.6, 7 July 2017

- Fetch old commit message when updating a PR. Previously we would try to
  rebuild the commit message from the PR message, but that often caused us
  to include extra, irrelevant details.

## v0.10.5, 7 July 2017

- Ensure git dependencies aren't updated as a result of https change

## v0.10.4, 7 July 2017

- Avoid using SSH to fetch dependencies - always use HTTPS. Ensures the
  GitHub credentials we pass to Bundler are used.

## v0.10.3, 7 July 2017

- Use Bundler settings to handle GitHub credentials

## v0.10.2, 6 July 2017

- Robust support for https auth details

## v0.10.1, 6 July 2017

- Revert handling git auth details for https specifications

## v0.10.0, 6 July 2017

- More robust file URL generation
- Notify about all unreachable git dependencies at once
- Handle git auth details for https specifications
- BREAKING: renamed GitCommandError and PathBasedDependencies errors

## v0.9.8, 6 July 2017

- Set path in Ruby File Updater, to fix path based dependencies (v2)

## v0.9.7, 6 July 2017

- Set path in Ruby File Updater, to fix path based dependencies

## v0.9.6, 6 July 2017

- Raise PathBasedDependencies error at file fetcher time for bad paths

## v0.9.5, 6 July 2017

- Only hit Rubygems once for each latest_version lookup
- Handle path-based Ruby dependencies, if possible

## v0.9.4, 2 July 2017

- Correctly list path-based dependencies

## v0.9.3, 1 July 2017

- Replace less than matcher (and <= matcher) with ~> during file updates
- Handle Ruby version constraints for dependencies Dependabot itself relies on

## v0.9.2, 30 June 2017

- Bump yarn (fixes non-deterministic lockfile generation)

## v0.9.1, 29 June 2017

- Cache `commit` in file fetcher, and ensure files fetched are for that commit

## v0.9.0, 29 June 2017

- BREAKING: Drop Dependabot::Repo in favour of just passing the repo's name

## v0.8.10, 29 June 2017

- Better tag/release lookup: handle completely unprefixed tags/releases

## v0.8.9, 28 June 2017

- FIX: Honour Ruby version when determining latest resolvable version

## v0.8.8, 26 June 2017

- FIX: Improved Bundler bug workaround, with specs

## v0.8.7, 26 June 2017

- FIX: Work around Bundler bug when doing Ruby update checks

## v0.8.6, 21 June 2017

- FIX: Pass GitHub credentials as `x-access-token` password. This allows us to
  clone private repos using app access tokens, whilst maintaining support for
  doing so using OAuth tokens.

## v0.8.5, 20 June 2017

- Clean version strings in JavaScript parser

## v0.8.4, 20 June 2017

- FIX: Require Octokit and Gitlab where used

## v0.8.3, 14 June 2017

- Full support for Bitbucket changelogs and commit comparisons

## v0.8.2, 13 June 2017

- Full support for GitLab changelogs, release notes, and commit comparisons

## v0.8.1, 13 June 2017

- Link to GitLab dependency sources, too

## v0.8.0, 13 June 2017

- BREAKING: drop support for Ruby 2.3
- Link to Bitbucket dependency sources (and lay groundwork for changelogs etc.)

## v0.7.10, 12 June 2017

- Improve commit comparison URL generation (handle arbitrary prefixes)

## v0.7.9, 9 June 2017

- Handle npm packages with an old 'latest' tag

## v0.7.8, 8 June 2017

- Strip leading 'v' prefix from PHP version strings

## v0.7.7, 7 June 2017

- Return fetched dependency file contents as UTF-8

## v0.7.6, 7 June 2017

- Don't blow up when deps are missing from yarn.lock

## v0.7.5, 7 June 2017

- Ignore JS prerelease versions
- Use HTTPS when talking to the NPM registry

## v0.7.4, 7 June 2017

- Handle PHP composer.json files that specify a PHP version / extensions

## v0.7.3, 3 June 2017

- Minor improvement to GitHub release finding (finds unnamed releases)

## v0.7.2, 3 June 2017

- Update pull request titles to include from-version

## v0.7.1, 2 June 2017

- Add short-circuit lookup for update checkers

## v0.7.0, 2 June 2017

- Rename to dependabot-core

## v0.6.5, 01 Jun 2017

- Fix PHP issues from initial beta test (#61)

## v0.6.4, 01 Jun 2017

- Add support for PHP (Composer) projects

## v0.6.3, 30 May 2017

- Even better version pattern updating for JS

## v0.6.2, 29 May 2017

- Better version pattern updating for JS

## v0.6.1, 29 May 2017

- Make yarn run in non-interactive mode

## v0.6.0, 29 May 2017

- BREAKING: Organise by package manager, not language (#55)
- BREAKING: Refactor error handling (#54)

## v0.5.8, 24 May 2017

- Don't change yarn.lock version comments (#53)

## v0.5.7, 24 May 2017

- Ignore exotic (git, path, etc) JavaScript dependencies (#52)

## v0.5.6, 23 May 2017

- Raise a bespoke error for Ruby path sources (#51)

## v0.5.5, 22 May 2017

- Back out CocoaPods support, since it pins ActiveSupport to < 5 (#50)

## v0.5.4, 22 May 2017

- Look for any release ending with the dependency version (#49)

## v0.5.3, 18 May 2017

- Slightly shorter branch names (#43)
- Do JavaScript file updating in JavaScript (#41)

## v0.5.2, 17 May 2017

- Include details of the directory (if present) in the PR name (#40)

## v0.5.1, 17 May 2017

- Raise Bump::VersionConflict if a conflict stops us getting a gem version (#38)
- Use folders for branch names, and namespace under language and directory (#39)

## v0.5.0, 16 May 2017

- Extract the correct versions of JavaScript dependencies in the parser (#36)
- Consider resolvability when calculating latest_version in Ruby (#35)
- BREAKING: require `github_access_token` when creating an UpdateChecker

## v0.4.1, 15 May 2017

- Allow `pr_message_footer` argument to be passed to `PullRequestCreator` (#32)

## v0.4.0, 15 May 2017

- BREAKING: Make language a required attribute for Bump::Dependency (#29)
- Handle PR creation races gracefully (#31)
- Minor improvement to PR text

## v0.3.4, 12 May 2017

- Better JavaScript and Python metadata finding
- Exposed `.required_files` method on dependency file fetchers

## v0.3.3, 11 May 2017

- Escape scoped package names in MetadataFinders::JavaScript (#27)
- Look for JavaScript GitHub link in most recent releases first (#28)

## v0.3.2, 09 May 2017

-  Don't discard DependencyFile details when updating (#24)

## v0.3.1, 09 May 2017

-  Support fetching dependency files from a specified directory (#23)


## v0.3.0, 09 May 2017

-  BREAKING: Rename Node to JavaScript everywhere (#22)

## v0.2.1, 03 May 2017

-  Store the failed git command on GitCommandError (#21)

## v0.2.0, 02 May 2017

- BREAKING: Rename Bump::FileUpdaters::VersionConflict (#20)

## v0.1.7, 02 May 2017

- Add DependencyFileNotEvaluatable error (#17)

## v0.1.6, 02 May 2017

- Stop updating RUBY VERSION and BUNDLED WITH details in Ruby lockfiles (#18)
- Handle public git sources gracefully (#19)

## v0.1.5, 28 April 2017

- Add PullRequestUpdate class (see #15)
- Raise a Bump::DependencyFileNotFound error if files can't be found (see #16)

## v0.1.4, 27 April 2017

- Handle 404s for Rubygems when creating PRs (see #13)
- Set backtrace on errors raised in a forked process (see #11)

## v0.1.3, 26 April 2017

- Ignore Ruby version specified in the Gemfile (for now) (see #10)

## v0.1.2, 25 April 2017

- Support non-Rubygems sources (so private gems can now be bumped) (see #8)
- Handle all exceptions in forked process (see #9)

## v0.1.1, 19 April 2017

- Follow redirects in Excon everywhere (fixes #4)

## v0.1.0, 18 April 2017

- Initial extraction of core logic from https://github.com/gocardless/bump
