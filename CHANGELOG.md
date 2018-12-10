## v0.79.3, 10 December 2018

- Python: Update requirement path in PipfileVersionResolver
- Exclude merge commits when looking for latest dependabot commit message

## v0.79.2, 9 December 2018

- Python: Catch ValueError and treat as a FileNotEvaluatable error

## v0.79.1, 9 December 2018

- Python: Add system dependencies into Dockerfile

## v0.79.0, 9 December 2018

- Extract python logic into a separate gem
- Yarn: Fix lockfile for invalid resolutions

## v0.78.0, 7 December 2018

- Extract git_submodules logic into a separate gem

## v0.77.2, 7 December 2018

- Add top level docker file that requires docker classes

## v0.77.1, 7 December 2018

- Simplify dependabot-docker gemspec
- Add /pkg to gitignore

## v0.77.0, 7 December 2018

- Move Docker support to a separate gem

## v0.76.11, 7 December 2018

- Python: Ignore dependencies that we had to insert a version for
- JS(npm): Raise helpful errer for forbidden missing deps
- Gradle: Don't consider dependencies that concatenate properties to build a version
- Maven: Check distribution type when looking up declaration to update

## v0.76.10, 6 December 2018

- Cache commit tag lookup in changelog finder
- Sanitize relative links in release notes

## v0.76.9, 6 December 2018

- Python: Handle bare version requirements in the RequirementUpdater

## v0.76.8, 6 December 2018

- JS: Build relative paths for path dependencies of unfetchable path
  dependencies
- JS: Get correct version for path dependencies

## v0.76.7, 6 December 2018

- No code changes - testing automated releases

## v0.76.6, 6 December 2018

- No code changes - testing automated releases

## v0.76.5, 6 December 2018

- Add omnibus gem

## v0.76.4, 6 December 2018

- No code changes - testing automated releases

## v0.76.3, 6 December 2018

- Start releasing to RubyGems
- Fix gemspec warnings

## v0.76.2, 6 December 2018

- Better detection of dependabot commit when updating a PR

## v0.76.1, 5 December 2018

- JS: Don't check for yanked packages if using a private registry
- Rust: Ensure parsed version matches requirement source
- PHP: Bump composer/composer from 1.7.3 to 1.8.0

## v0.76.0, 5 December 2018

- Terraform: (BREAKING) Split Terraform support out into a separate gem, still
  within the same repo. See #825 for more info.
- Maven: Handle credentials that don't include auth details
- Convert relative links in changelogs and release notes

## v0.75.126, 5 December 2018

- .NET: Pass URL string (not hash) when raising PrivateSourceTimedOut

## v0.75.125, 5 December 2018

- JS: Raise a resolvability error for invalid requirements

## v0.75.124, 4 December 2018

- JS: Raise an authentication error for private, unscoped packages
- JS: Handle `_npmUser` entries without a name

## v0.75.123, 4 December 2018

- Go: Use correct file path when raising DependencyFileNotParseable

## v0.75.122, 4 December 2018

- JS: Recursively fetch path dependencies

## v0.75.121, 4 December 2018

- Java: Handle null values in version strings

## v0.75.120, 2 December 2018

- JS: Handle missing `_npmUser` details

## v0.75.119, 2 December 2018

- Add details of new maintainers to PRs (if they are the one that released
  this JS package)

## v0.75.118, 30 November 2018

- Detect capitalisation of first word in commit message
- Maven: Handle empty version tags
- Python: Don't error on pip-compile cascading resolution issues

## v0.75.117, 30 November 2018

- Better commit prefix detection

## v0.75.116, 30 November 2018

- .NET: Fetch the largest sln file, not the first
- Handle missing version/name in package.json

## v0.75.115, 30 November 2018

- Retry timeouts fetching git repos from known sources
- JS: Handle blank versions in FileParser

## v0.75.114, 29 November 2018

- JS: Fix check if install resolved before update
- JS: Handle versions without peer dependencies in latest_version_of_dep_with_satisfied_peer_reqs

## v0.75.113, 29 November 2018

- Detect ESLint commit messages that include scopes

## v0.75.112, 29 November 2018

- Docker: Handle persistent 404s from Dockerhub
- PHP: Handle updates to a manifest file where only one requirement needs to
  change

## v0.75.111, 29 November 2018

- Fix require problem that only affected requiring FileUpdaters first
- JS: Raise a resolvability error when a scoped package can't be found

## v0.75.110, 29 November 2018

- JS: Fetch path dependencies that are specified as links
- JS: Implement full unlock for resolving JS peer dependencies

## v0.75.109, 29 November 2018

- Use Bundler 1.17.1 in Dockerfile
- JS: Support updating multiple dependencies at once

## v0.75.108, 28 November 2018

- JS: More glob path improvements

## v0.75.107, 28 November 2018

- JS: Handle Yarn ignored package globs

## v0.75.106, 28 November 2018

- Don't match versions that are superstrings in changelog pruner
- Add Azure TODOs to metadata finders

## v0.75.105, 27 November 2018

- Handle symlinked files in FileFetcher

## v0.75.104, 27 November 2018

- Handle git dependencies for libraries

## v0.75.103, 26 November 2018

- Python: More tweaks to Pipenv environment handling
- Python: Parse pip_compile results more accurately

## v0.75.102, 26 November 2018

- Python: Use shared helper to switch python version
- Python: Better handling of bad python requirements (fix spec)

## v0.75.101, 26 November 2018

- Python: Switch to released Pipenv
- JS: Fetch npmrc and yarnrc files from parent directories if required
- Python: Raise a resolvability error if max retries are exceeded
- Python: Better environment setup during Pipenv UpdateChecker

## v0.75.100, 26 November 2018

- Correct upgrade type labeling for git dependencies

## v0.75.99, 26 November 2018

- Elixir: Don't join support file names with directory

## v0.75.98, 26 November 2018

- Elixir: Use supporting files when parsing, checking and updating
- Elixir: Fetch files that are evaled by mixfile

## v0.75.97, 25 November 2018

- Python: Bump pipenv commit

## v0.75.96, 24 November 2018

- Handle non-master bitbucket branches in ChangelogFinder

## v0.75.95, 24 November 2018

- Fall back to looking for changelog on specific tag if it can't be found on
  master

## v0.75.94, 24 November 2018

- Python: Bump Pipenv to latest commit

## v0.75.93, 23 November 2018

- Docker: Retry rogue 404s from dockerhub

## v0.75.92, 23 November 2018

- Python: Lock git dependencies during Pipenv updates

## v0.75.91, 23 November 2018

- Python: Handle Pipfiles without a source block
- Better GitHub repo regex (taken directly from Octokit)

## v0.75.90, 23 November 2018

- Python: Try setting a longer pip default timeout

## v0.75.89, 23 November 2018

- Python: Raise a resolvability error for unsupported dependencies
- Go (dep): Fix fsnotify-related bug in the update checker

## v0.75.88, 23 November 2018

- Python: Handle path dependencies in Pipenv everywhere

## v0.75.87, 23 November 2018

- Bump poetry from 0.12.9 to 0.12.10
- Use latest Pipenv commit and remove workaround
- npm: ingore platform and engine checks on install
- Python: Fetch path dependencies listed in Pipfile
- Python: Mark fetched path dependencies as support files

## v0.75.86, 22 November 2018

- Python: Workaround Pipenv bug (caused issue for new Python version installs)

## v0.75.85, 22 November 2018

- Python: Use latest pipenv commit (prep for imminent release)

## v0.75.84, 22 November 2018

- Dep: Silence a relatively hard-to-reproduce dep panic
- PHP: Fetch auth.json (in preparation for using it)

## v0.75.83, 22 November 2018

- Handle a nil that previously wasn't being handled

## v0.75.82, 22 November 2018

- Don't assume a `~/.gitconfig` exists

## v0.75.81, 22 November 2018

- Go (dep): handle fsnotify bug
- Fix some issues relating to git credentials configuration

## v0.75.80, 21 November 2018

- Python: Interpret additional pip-compile error as tell that Python 2.7 should
  be used

## v0.75.79, 21 November 2018

- Ruby: Handle calls to Find.find in gemspecs

## v0.75.78, 21 November 2018

- Ruby: Smarter gemspec sanitization (wrap require lines in error handling,
  rather than deleting them)

## v0.75.77, 21 November 2018

- Ruby: Better readlines replacement

## v0.75.76, 21 November 2018

- .NET: Assume unfound properties are up-to-date
- Ruby: Sanitize File.readlines from gemspec

## v0.75.75, 21 November 2018

- Python: Better checking of Python version when using Pipenv
- Python: Handle python requirements with an || in pyproject.toml

## v0.75.74, 20 November 2018

- JS: Fix dependency updates with os requirements (npm)

## v0.75.73, 20 November 2018

- Trim spec.files in gemspec, speeding up docker development
- Fix typo in Poetry updater

## v0.75.72, 20 November 2018

- Python: Another attempt to fix poetry
- JS: Handle outdated git source in lockfile

## v0.75.71, 20 November 2018

- Python: Try updating pip for installing requirements

## v0.75.70, 20 November 2018

- Python: Install all requirments for different python versions

## v0.75.69, 20 November 2018

- Go (dep): ignore some tricky git dependencies

## v0.75.68, 20 November 2018

- Maven: Allow version updates that come via a parent_pom
- Python: Sanitize pyproject.toml files before running Poetry

## v0.75.67, 20 November 2018

- Rust: Handle git sub-dependencies
- .NET: Handle unfound property versions in VersionFinder
- Python: Bump poetry from 0.12.8 to 0.12.9
- Elixir: Handle unevaluatable Mixfiles
- Docker: Handle Dockerhub 404s when looking up latest version digest
- JS: Handle unreachable git dependencies in Yarn lockfile updater

## v0.75.66, 19 November 2018

- PHP: Raise dependency file not resolvable if tarball can't be downloaded
- Switch back to using --global for git configuration

## v0.75.65, 19 November 2018

- JS: Handle no lockfile when completing npmrc
- JS: Raise git not reachable for ssh://git

## v0.75.64, 19 November 2018

- JS: Handle environment variables in npmrc in unexpected places

## v0.75.63, 19 November 2018

- Go (modules): catch go.mod major version issues in the parser

## v0.75.62, 19 November 2018

- Ruby: Better gemspec sanitization (handle tapped blocks)

## v0.75.61, 18 November 2018

- .NET: Handle ruby-stype requirement strings

## v0.75.60, 18 November 2018

- Python: Better Python version error handling for pip-compile
- JS: Remove comments before parsing package.json (they shouldn't be there
  anyway...)

## v0.75.59, 18 November 2018

- Python: Handle sub-dependency updates where the sub-dep is no longer required

## v0.75.58, 18 November 2018

- .NET: Don't raise for uninterpolated versions
- Raise Dependabot::OutOfMemory if Composer runs out of memory

## v0.75.57, 18 November 2018

- .NET: Handle requirement strings in .NET format

## v0.75.56, 17 November 2018

- Ruby: Handle Bundler 2 lockfiles
- JS: Make tarball protocol consistent when updating from http to https

## v0.75.55, 17 November 2018

- Python: Boost Pipenv timeout to 10 minutes

## v0.75.54, 16 November 2018

- Python: Update unsafe requirements if specified in pip-compile manifest

## v0.75.53, 16 November 2018

- Python: Protect against fetching the same file multiple times
- Python: Order pip-compile file resolution correctly when .txt outputs are
  imported

## v0.75.52, 16 November 2018

- Ruby: Use Bundler 2.0.0.pre.1
- Try to prevent Sentry from grouping all HelperSubprocessFailed errors
- Elm: Don't perform updates that require indirect dependency changes

## v0.75.51, 16 November 2018

- Handle changelogs which use a bullet point for each new version

## v0.75.50, 16 November 2018

- Ruby: Prefer fetching gems.rb to Gemfile
- Python: decrease timeout from 500 to 360 seconds
- JS: Mute sub-dependency version resolve errors

## v0.75.49, 15 November 2018

- Python: Set higher timeout for Pipenv

## v0.75.48, 15 November 2018

- Python: Clean up Pipenv error handling

## v0.75.47, 15 November 2018

- Python: Raise original error correctly depending on Python version in use
- Maven: Fix DeclarationFinder when looking up declaration in a pom with missing
  properties

## v0.75.46, 15 November 2018

- Maven: Handle property searches that use a range for the parent pom

## v0.75.45, 15 November 2018

- Python: Disable pipenv spinner in logs
- .NET: Longer timeout when hitting registries
- Rust: Retry timeouts from crates.io

## v0.75.44, 15 November 2018

- PHP: Respect COMPOSER_MEMORY_LIMIT environment variable

## v0.75.43, 15 November 2018

- JS: Handle tricky possible version comparisons
- Python: Switch to released version of pipenv
- Elm: Select elm resolver based on requirements

## v0.75.42, 14 November 2018

- Go modules: strip whitespace from parser errors

## v0.75.41, 14 November 2018

- Go: Better parser error handling for Go modules
- JS: Handle diverged npm/yarn lockfiles
- JS: Fix bug when using both npm5 and yarn lockfiles and updating a sub-dep

## v0.75.40, 14 November 2018

- Python: Pin to latest pipenv commit
- JS: Handle bad peer dependency requirements

## v0.75.39, 14 November 2018

- Python: Bump poetry from 0.12.7 to 0.12.8
- Python: Bump hashin from 0.13.4 to 0.14.0

## v0.75.38, 13 November 2018

- JS: Support updating npm sub-dependencies
- Python: Handle transition from a single hash to multiple in requirements file
  updater
- JS: Handle unmet peer dependency warnings in yarn

## v0.75.37, 12 November 2018

- JS: Add npm-shrinkwrap to list of files updated by file updater
- Python: More careful requirement file updating (handle no-binary flags)

## v0.75.36, 10 November 2018

- JS: Handle npm switches to insecure URLs

## v0.75.35, 9 November 2018

- Ruby: Simpler error message from FileFetcher

## v0.75.34, 9 November 2018

- Python: Handle quote characters when fetching path dependencies
- Python: Bump poetry from 0.12.6 to 0.12.7

## v0.75.33, 8 November 2018

- Python: Don't confuse git reference with path references when fetching files

## v0.75.32, 8 November 2018

- Use ESLint style commit messages if they're currently in use

## v0.75.31, 8 November 2018

- JS: Retry transitory errors in SubdependencyVersionResolver
- JS: Retry another transitory error in YarnLockfileUpdater
- Python: Better handling of cases when attempting a pip-compile update would
  cause errors

## v0.75.30, 8 November 2018

- Elixir: Better error checking (raise based on original reqs)
- Elixir: Handle resolution failure for git dependencies

## v0.75.29, 8 November 2018

- Elixir: Raise DependencyFileNotResolvable error for unresolvable mixfiles

## v0.75.28, 7 November 2018

- JS: Better whitespace escaping
- PHP: Handle packages that require themselves

## v0.75.27, 7 November 2018

- JS: Fix sanitization when a slash character is being escaped

## v0.75.26, 7 November 2018

- JS: Better parsing of private registry URLs
- JS: Bump yarn from 1.12.1 to 1.12.3

## v0.75.25, 7 November 2018

- .NET: Parse and update nested packages.config files

## v0.75.24, 7 November 2018

- .NET: Fetch packages.config files from any directories specified in .sln files

## v0.75.23, 7 November 2018

- JS: Fix yarn lockfile for githost shorthand installs

## v0.75.22, 7 November 2018

- JS: Don't consider previously failing peer dependencies when finding latest
  resolvable version

## v0.75.21, 7 November 2018

- Rejig semantic prefix detection

## v0.75.20, 7 November 2018

- JS: Don't try to version resolve git dependencies
- JS: Better caching in UpdateChecker

## v0.75.19, 6 November 2018

- JS: Handle complicated requirements

## v0.75.18, 6 November 2018

- Python: Fetch path dependencies with paths that don't start with a '.'

## v0.75.17, 6 November 2018

- Fix merge conflict issue in FileFetchers::Base

## v0.75.16, 6 November 2018

- Python:  Bump poetry from 0.12.5 to 0.12.6
- JS: Handle version resolution for sub-dependencies when not updating manifest
- Add a common interface for provider client (thanks @codisart)

## v0.75.15, 5 November 2018

- Python: Handle or conditions in Poetry python requirements

## v0.75.14, 5 November 2018

- JS: Stop downloading node_modules when checking yarn peer deps
- Docker: Handle ignored versions

## v0.75.13, 5 November 2018

- Ruby: Better error handling if Gemfile isn't present
- Ruby: Fix typo in FileParser
- Ruby: Handle assignment to an integer in GemspecSanitizer

## v0.75.12, 4 November 2018

- JS: Fix bug in peer dependency checks for yarn
- Ruby: Handle gems.rb and gems.locked

## v0.75.11, 3 November 2018

- JS: Log all peer dependency warnings from yarn and npm

## v0.75.10, 3 November 2018

- .NET: Don't assume lowest version is the current one in file parser
- Python: Handle sub-dependencies that appear in a requirements.txt

## v0.75.9, 2 November 2018

- JS: Better peer dependency regex for npm
- JS: Better git dependency handling in peer dependency checker

## v0.75.8, 2 November 2018

- go: only download packages with go get, don't build them

## v0.75.7, 2 November 2018

- Maven: Check whether property being updated has the same source
- Maven: Store property source in metadata, as well as name

## v0.75.6, 2 November 2018

- Go: Fix go.sum updating

## v0.75.5, 2 November 2018

- Docker: Include registry details if auth failure happens on Docker Hub
- Maven: Handle range requirements for parent when finding custom repositories
- Rust: Raise an error when trying to operate on a non-root part of a rust
  workspace

## v0.75.4, 2 November 2018

- JS: Add workaround for git dependency library updates

## v0.75.3, 2 November 2018

- Gradle: Handle dependency set updating when the dependency set has been
  updated already

## v0.75.2, 2 November 2018

- Python: Don't write .python-version when updating Pipfile or pip-compile files
- PHP: Bump composer/composer from 1.7.2 to 1.7.3

## v0.75.1, 1 November 2018

- JS: Hot fixes for VersionResolver

## v0.75.0, 1 November 2018

- JS: First attempt at handling JS peer dependencies

## v0.74.26, 1 November 2018

- Handle case with no previous dependabot PRs

## v0.74.25, 1 November 2018

- Use `chore` as semantic commit message if it is being used

## v0.74.24, 1 November 2018

- Yarn: Fix resolved url in lockfile for dependencies installed from GitHub using the
  shorthand syntax (without host)

## v0.74.23, 1 November 2018

- Python: Handle upper bound changes when new version has fewer digits than old
  one

## v0.74.22, 31 October 2018

- Python: Handle custom python versions when using Poetry

## v0.74.21, 31 October 2018

- JS: Bump yarn from 1.10.1 to 1.12.1

## v0.74.20, 31 October 2018

- Python: Don't use python-version declared in .python-version file
- JS: Save some requests when fetching path dependencies
- Python: Bump poetry from 0.11.5 to 0.12.5

## v0.74.19, 30 October 2018

- Add Azuze as a known source
- Rust: Handle yanked versions in UpdateChecker when not using a lockfile

## v0.74.18, 29 October 2018

- Python: Handle 403s more intelligently in UpdateChecker

## v0.74.17, 29 October 2018

- Rust: Handle resolvability errors that exist in the initial requirements

## v0.74.16, 28 October 2018

- .NET: Look up property values that include further indirection
- .NET: Store the root property name when parsing dependencies (not the
  top-level one)

## v0.74.15, 28 October 2018

- Elixir: Ignore non-existant apps_path
- JS: Consider global registry in RegistryFinder
- JS: Handle timeout errors from private registries in FileUpdater
- JS: Fall back to global registry, rather than registry.npmjs.org, in
  RegistryFinder

## v0.74.14, 28 October 2018

- Maven: Raise a PrivateSourceAuthenticationFailure if auth stopped us finding
  any versions of a dependency
- Maven: Don't hit password protected registries without password
- Maven: More careful caching of dependency metadata in VersionFinder

## v0.74.13, 27 October 2018

- Python: Make requirement updating logic depend on whether a lockfile is
  present

## v0.74.12, 27 October 2018

- Python: Only update poetry dev dependency requirements if the update
  is required

## v0.74.11, 26 October 2018

- Python: Raise a DependencyFileNotResolvable error for yanked dependencies

## v0.74.10, 26 October 2018

- Rust: Handle invalid names in manifest files (assuming no lockfile)

## v0.74.9, 26 October 2018

- Ignore merge commits when determining whether conventional commits are in use

## v0.74.8, 25 October 2018

- Go: Add method to look up Go paths without using Go (for environments where
  we don't have the binaries)

## v0.74.7, 25 October 2018

- dep: rewrite vcs remote lookup in go using native library
- Paginate through long lists of labels

## v0.74.6, 25 October 2018

- JS: Don't update the  attribute for git dependencies in npm6 lockfiles
- Rust: Guard against trying to update dependencies with multiple source types

## v0.74.5, 25 October 2018

- Go (modules): Update the go.sum if present
- JS: Use lockfile to determine global registry if a .yarnrc exists but doesn't
  specify it

## v0.74.4, 25 October 2018

- Python: Use pip-tools' --allow-unsafe option when required

## v0.74.3, 25 October 2018

- Python: Fix typo

## v0.74.2, 24 October 2018

- Python: Handle Pipenv updates that need Python two

## v0.74.1, 24 October 2018

- Go: Add go_modules into the metadata finders map

## v0.74.0, 24 October 2018

- Go: Less broken support for Go modules, now in a separate package manager

## v0.73.87, 24 October 2018

- Python: More Python version management

## v0.73.86, 24 October 2018

- Python: Don't use a user's .python-version when running our own python helpers

## v0.73.85, 24 October 2018

- Elixir: Better timeout logic
- JS: Add test that having a frozen Yarn lockfile doesn't affect file updating
- Python: Better Python version detection, and management

## v0.73.84, 23 October 2018

- Java: Normalise date versions before comparing

## v0.73.83, 23 October 2018

- Python: Fetch .python-version files
- Elixir: Don't overwrite @latest_resolvable_version in UpdateChecker
- Python: Add an additional Pipenv retry
- Elixir: Handle (ignore) timeouts

## v0.73.82, 23 October 2018

- JS: Switch all ssh URLs to ssl when updating a package-lock.json

## v0.73.81, 22 October 2018

- Ruby: Handle ignore requirements which prevent the current version

## v0.73.80, 22 October 2018

- Reject changelog candidates that have an invalid encoding

## v0.73.79, 22 October 2018

- .NET: Ensure Directory.Build.props is fetched

## v0.73.78, 22 October 2018

- Python: More robust pip config file updating
- Python: Check resolvability of all requirement files in
  PipCompileVersionResolver
- Python: Recursively determine order to compile pip-compile files

## v0.73.77, 21 October 2018

- Python: Catch another equality matcher case

## v0.73.76, 21 October 2018

- Python: Handle cascading pip-compile requirements when updating files
- Python: Better handling of pip-compile errors during version resolution
- Python: More robust child requirement file path building

## v0.73.75, 21 October 2018

- Gradle: Handle dependency sets nicely in PR creator

## v0.73.74, 21 October 2018

- Gradle: Add support for dependencySet dependencies
- Python: Handle Poetry file updates without a lockfile

## v0.73.73, 20 October 2018

- Handle directory paths that instead point to a file
- Ruby: Handle equality matcher when determining required comment change

## v0.73.72, 20 October 2018

- Java: Trim v-prefices from version strings when comparing
- JS: Handle 401s in same way as 403s when updating npm lockfiles

## v0.73.71, 20 October 2018

- JS: Raise a PrivateSourceAuthenticationFailure error when we can't find deps
  from private sources
- Ruby: More careful sanitization of gemspecs

## v0.73.70, 19 October 2018

- Python: Raise original error if retrying on Python 2.7

## v0.73.69, 19 October 2018

- Python: Add Cython as a dependency

## v0.73.68, 18 October 2018

- Python: Stricter index finding regex
- Python: Ensure local version is unset after each check

## v0.73.67, 17 October 2018

- Python: Support poetry.lock
- Python: Less strict suffix removal

## v0.73.66, 15 October 2018

- Python: Switch to Pipenv 2018.10.13

## v0.73.65, 15 October 2018

- Python: Handle unfixable requirements gracefully

## v0.73.64, 14 October 2018

- JS: Ensure lockfile updates for Yarn workspace have the correct requirements

## v0.73.63, 14 October 2018

- Rust: Don't unlock version is support files during update check

## v0.73.62, 13 October 2018

- JS: Handle dist tags when updating the lockfile only

## v0.73.61, 13 October 2018

- Handle unexpected 409s from GitHub when fetching files

## v0.73.60, 12 October 2018

- JS: Better expansion of workspace paths (fix paths starting './')

## v0.73.59, 12 October 2018

- JS: Handle git dependencies without a resolution in the lockfile

## v0.73.58, 12 October 2018

- JS: Handle git dependencies where the resolved source uses a slash, not a #

## v0.73.57, 11 October 2018

- .NET: Handle dependency_urls tags that start with a number
- Python: Handle single equality sign matcher (Poetry)

## v0.73.56, 11 October 2018

- Ruby: Sanitize gemspec version property when assigned to `File.read(..)`

## v0.73.55, 11 October 2018

- Python: Use git commit for pipenv

## v0.73.54, 10 October 2018

- Bump Python and Go versions, and add LANG environment variable (Dockerfile)
- JS: Add first version of Yarn subdependency updating

## v0.73.53, 9 October 2018

- Update Pipenv to 2018.10.9

## v0.73.52, 8 October 2018

- Prefer lower versions when parsing dependencies into DependencySet

## v0.73.51, 8 October 2018

- JS: More multiple-source handling
- Python: Handle replacement for strings separated with a period

## v0.73.50, 8 October 2018

- PHP: Mark Composer path dependencies as support files

## v0.73.49, 8 October 2018

- Make GitCommitChecker more lenient about multiple git sources

## v0.73.48, 8 October 2018

- Python: Bump pip from 18.0 to 18.1
- Python: Bump pip-tools from 3.0.0 to 3.1.0
- Rust: Handle dependencies with multiple sources in file fetcher

## v0.73.47, 7 October 2018

- Bump Bundler and Rust versions in Dockerfile
- Go: More robust git source lookup
- JS: Handle npm bug (by serving a resolvability error)

## v0.73.46, 6 October 2018

- Python: Ensure Pipenv uses Pip 18.0

## v0.73.45, 6 October 2018

- Ruby: Don't update to pre-release versions during full_unlock
- JS: Stricter source finding

## v0.73.44, 4 October 2018

- Elixir: Handle `nil` requirements in file preparer

## v0.73.43, 4 October 2018

- JS: Handle outdated git requirement in parser
- JS: Handle yarn workspaces that use nohoist

## v0.73.42, 4 October 2018

- JS: Use yarnrc file to build basis of npmrc file if present

## v0.73.41, 4 October 2018

- Python: Fetch Pipenv, Poetry and pip-tools files first
- If multiple changelogs are present, pick one that includes the version

## v0.73.40, 4 October 2018

- Docker: Don't try to handle SHA versions even if there is a 'latest' tag

## v0.73.39, 4 October 2018

- Docker: Exclude versions that are just a SHA

## v0.73.38, 3 October 2018

- PHP: Detect OR separator in use and replicate it
- Docker: Add filter for SHA-like suffices to Docker version checking

## v0.73.37, 3 October 2018

- Python: Better file updater requirement comparison
- JS: Ignore dependencies with multiple sources

## v0.73.36, 3 October 2018

- Docker: Don't assume that private registries use 'libraries' prefix

## v0.73.35, 2 October 2018

- Docker: Speed up UpdateChecker
- Introduce new `support_file` attribute on DependencyFile instances

## v0.73.34, 1 October 2018

- Python: Ignore dependencies with a < or <= python version marker

## v0.73.33, 1 October 2018

- Better PR number sanitization
- Docker: Handle 403s during tag and digest fetching

## v0.73.32, 1 October 2018

- More robust Bitbucket commit lookup

## v0.73.31, 30 September 2018

- JS: Handle npm lockfiles that specify a numeric version for a git dependency

## v0.73.30, 29 September 2018

- Docker: Handle 403 responses when authenticating

## v0.73.29, 29 September 2018

- Docker: Handle AWS ECR hosted images

## v0.73.28, 29 September 2018

- Elixir: Always use 3dp when using >= matcher
- Elixir: Improve check_update logic

## v0.73.27, 28 September 2018

- Ruby: Sanitize require_paths, rather than require_path

## v0.73.26, 28 September 2018

- Ruby: Sanitize `require_path` in gemspec

## v0.73.25, 28 September 2018

- Take even more care when processing upload packs

## v0.73.24, 28 September 2018

- Python: More precise lookup of requirement to update in requirements.txt
- PHP: Raise PrivateSourceTimedOut error if private sources time out

## v0.73.23, 28 September 2018

- Add BitBucket support in FileFetcher

## v0.73.22, 28 September 2018

- JS: Consider shrinkwraps when trying to determine a version
- More robust lookup of branch/ref git SHA

## v0.73.21, 27 September 2018

- JS: Handle workspace path that is just an asterisk

## v0.73.20, 27 September 2018

- Ruby: Only fetch path gemspecs once
- JS: Add version and private keys to helper package.json files

## v0.73.19, 27 September 2018

- JS: Bump @dependabot/yarn-lib from 1.10.0 to 1.10.1
- JS: Better check for Yarn version

## v0.73.18, 26 September 2018

- JS: Bump @dependabot/yarn-lib from 1.9.4 to 1.10.0 in /helpers/yarn

## v0.73.17, 25 September 2018

- JS: Retry 500s from registry using different auth strategy

## v0.73.16, 25 September 2018

- JS: Handle multiple private registries with the same host
- JS: Remove npm bug workaround
- Handle multiple GitHub credentials

## v0.73.15, 25 September 2018

- Ruby: Don't sanitize gemspec descriptions (may be used alongside summary)
- Go: Handle +incompatible suffices
- Python: Bump pip-tools from 2.0.2 to 3.0.0 in /helpers/python

## v0.73.14, 24 September 2018

- Ruby: Handle HEREDOC strings when sanitizaing gemspec

## v0.73.13, 24 September 2018

- Ruby: Fix tests and gemspec sanitization

## v0.73.12, 24 September 2018

- JS: Handle private registries that end with a trailing slash
- Better error path sanitization
- Ruby: More aggressive gemspec sanitization

## v0.73.11, 24 September 2018

- .NET: Exclude dependency declarations that use interpolation
- Python: Handle names that need to be sanitized when looking up in Pipfile.lock

## v0.73.10, 23 September 2018

- .NET: Handle mutli-dependency property updates

## v0.73.9, 23 September 2018

- .NET: Handle inherited properties in FileUpdater

## v0.73.8, 22 September 2018

- .NET: Handle inherited properties in PropertyValueFinder

## v0.73.7, 21 September 2018

- Go: Better determination of whether a dependency is using Dep
- .NET: Fetch Directory.Build.props files
- Docker: Remove unneeded "type" key in source details

## v0.73.6, 21 September 2018

- Rust: Recognise branch not found errors and raise then

## v0.73.5, 21 September 2018

- Ruby: Sanitize gemspec by removing all File.read calls
- Always sanitize file paths in errors

## v0.73.4, 21 September 2018

- Gradle: Stricter regex for groupId and artifactId parts

## v0.73.3, 20 September 2018

- Python: Fix bug in Poetry file preparation
- Go: Add workaround for Dep bug with gopkg.in/fsnotify.v1

## v0.73.2, 20 September 2018

- Gradle: Stricter regex for groupId and artifactId parts
- Python: Pip Poetry git dependencies correctly

## v0.73.1, 20 September 2018

- Maven: Use Maven default groupID when parsing plugins that don't specify one
- Maven: Handle plugins which don't specify a groupId in FileUpdater

## v0.73.0, 20 September 2018

- BREAKING: Update the base branch of a PR when updating it, if necessary.
  If you weren't passing a `Source` with a branch when updating PRs which had a
  custom base branch you will now need to

## v0.72.21, 20 September 2018

- Maven: Allow multi-dependency property updates where some deps can't be found
- Maven: Update setting parser regexp to quote project name

## v0.72.20, 19 September 2018

- Gradle: Better property value parsing (fixes FileUpdater regex problem)

## v0.72.19, 19 September 2018

- Rust: Ensure FileUpdater only updates version of the dependency being
  considered

## v0.72.18, 19 September 2018

- Gradle: Ignore commented out declarations in settings.gradle
- Gradle: Ignore missing projects

## v0.72.17, 19 September 2018

- Gradle: Handle custom path declarations in settings.gradle

## v0.72.16, 19 September 2018

- Python: Raise same error for all dependencies if handling resolution issue
- JS: Handle badly specified requirements more gracefully

## v0.72.15, 18 September 2018

- Go: Handle switches from git source to version source when using a go.mod

## v0.72.14, 18 September 2018

- Fix Dependabot::Source regex

## v0.72.13, 18 September 2018

- Go: Specify a branch when parsing git dependencies (even if nil)

## v0.72.12, 18 September 2018

- Gradle: Update properties that are inherited

## v0.72.11, 18 September 2018

- Go: Assume go.mod dependencies are being pinned to a ref if using git version
- JS: More specific package.json section updating
- JS: Update peer dependencies if updating a dev dependency

## v0.72.10, 18 September 2018

- Go: Parse git dependencies in go.mod as git dependencies

## v0.72.9, 17 September 2018

- JS: Don't attempt to update symlinked dependencies
- JS: Remove JFrog workaround

## v0.72.8, 17 September 2018

- JS: Add workaround for JFrog bug

## v0.72.7, 17 September 2018

- Rust: Consider `replace` section when determining path dependencies to pull
  down

## v0.72.6, 17 September 2018

- Go: Fix modules parser import (and add test)

## v0.72.5, 17 September 2018

- Bump Rust version in Dockerfile, and remove Java, Gradle and Groovy
- Go: Handle Gopkg.toml files without any constraints

## v0.72.4, 17 September 2018

- JS: Update npm-shrinkwrap files

## v0.72.3, 16 September 2018

- Gradle: Ignore dependencies that use properties we can't find
- .NET: Parse property versions
- .NET: Handle property value updates in FileUpdater
- .NET: Only attempt to update properties that affect a single dependency

## v0.72.2, 15 September 2018

- Go: Add PathConverter util and use it in UpdateChecker and MetadataFinder

## v0.72.1, 15 September 2018

- Go: Strip v from parsed go modules versions
- Go: Add "v" prefix to go.mod versions in FileUpdater

## v0.72.0, 15 September 2018

- Go: Add initial support for modules

## v0.71.21, 15 September 2018

- Gradle: Don't allow '@' characters in dependency names

## v0.71.20, 14 September 2018

- Maven: Evaluate properties in Maven repos whenever possible

## v0.71.19, 14 September 2018

- Gradle: Handle wildcard requirements in Utils::Java::Requirement
- Gradle: Update dynamic version requirements correctly

## v0.71.18, 13 September 2018

- Maven: Fix requirement updating for versions with multiple dashes

## v0.71.17, 13 September 2018

- Gradle: handle properties prefixed with `properties`, too
- Gradle: Update lines that include a property in their name

## v0.71.16, 13 September 2018

- Gradle: Better property lookup logic

## v0.71.15, 13 September 2018

- Gradle: Look up repository URLs based on the current project and its root
- Gradle: Don't parse Gradle Witness lines

## v0.71.14, 13 September 2018

- Gradle: Don't update SHA versions

## v0.71.13, 13 September 2018

- Gradle: Strip out comments before parsing files

## v0.71.12, 12 September 2018

- Gradle: Ignore bad URLs

## v0.71.11, 12 September 2018

- Rust: Handle creating versions from existing versions

## v0.71.10, 12 September 2018

- Gradle: Switch dependency and repository parsing to be regex-based
- Rust: Don't error on versions with build metadata

## v0.71.9, 12 September 2018

- .NET: Handle .nuproj file dependency declarations
- Gradle: Use regex to parse setttings.gradle

## v0.71.8, 12 September 2018

- .NET: Handle bespoke project extensions

## v0.71.7, 12 September 2018

- Better monorepo handling in ReleaseFinder

## v0.71.6, 12 September 2018

- .NET: Handle custom feeds without authentication details

## v0.71.5, 11 September 2018

- Ruby: Update subdependencies to a specific version

## v0.71.4, 11 September 2018

- .NET: Actually cache latest_version_details
- .NET: Ensure requirements don't change if req stays the same

## v0.71.3, 11 September 2018

- JS: Handle 403s in NpmLockfileUpdater
- JS: Handle npm inconsistencies better when updating Yarn lockfiles

## v0.71.2, 11 September 2018

- JS: Better sanitization of escaped whitespace

## v0.71.1, 11 September 2018

- .NET: Process repos even if all dependency files can't be fetched

## v0.71.0, 11 September 2018

- BREAKING: Rename `nuget_repository` credential to `nuget_feed`

## v0.70.7, 11 September 2018

- Python: Minor parsing improvement

## v0.70.6, 10 September 2018

- PHP: Handle packages provided by another package

## v0.70.5, 10 September 2018

- Python: Implement PEP-0503 properly (replace runs of characters with a single
  dash)
- Python: Add workaround for Pipfile.lock not normalising quoted names fully

## v0.70.4, 10 September 2018

- Python: Stop swallowing errors when parsing setup.py
- Python: Add alternative approach to parsing setup.py files
- Python: Fall back to new parsing approach in setup.py sanitization

## v0.70.3, 9 September 2018

- Elm: Treat indirect dependencies as sub-dependencies
- Elm: Raise DependencyFileNotParseable errors for invalid JSON
- Elm: More error handling in update checker

## v0.70.2, 9 September 2018

- Elm: Use Elm 0.19 update checker if an elm.json is present

## v0.70.1, 9 September 2018

- Elm: Add elm.json to the list of updated files for Elm

## v0.70.0, 9 September 2018

- Add support for Elm 0.19
- Updates the container Dependabot Core uses to v0.1.31 (which includes both
  Elm 0.18 and Elm 0.19)

## v0.69.43, 8 September 2018

- .NET: Switch to using search endpoint to find versions for v3 repos. Means
  that unlisted dependencies will be excluded
- .NET: Exclude unlisted dependencies fetched using v2 API

## v0.69.42, 7 September 2018

- Ruby: Handle rubygems responses without a source_code_uri key (happens for
  private repos)

## v0.69.41, 6 September 2018

- Python: Handle invalid requirements in requirements.txt files
- Python: Normalise name before checking if dep already exists

## v0.69.40, 6 September 2018

- Go: Clean up not found regex
- Ruby: Handle source_code_uri directories correctly

## v0.69.39, 6 September 2018

- Go: Better regex for dep repo access issues

## v0.69.38, 6 September 2018

- Rust: Don't prune out toolchain unnecessarily

## v0.69.37, 5 September 2018

- Rust: Raise error if nightly version required and no rust-toolchain provided
- Python: Ignore git dependencies for Poetry (for now)

## v0.69.36, 5 September 2018

- Assume no prereleases for git dependencies without a tag
- Python: Raise a resolvability error for bad Python ranges in Pipfile
- Python: Sanitize setup.py before use with pip-tool in UpdateChecker
- Python: Sanitize setup.py before use with pip-tool in FileUpdater

## v0.69.35, 5 September 2018

- Ruby: Handle gemfiles that are just a comment in GemfileChecker

## v0.69.34, 5 September 2018

- Exclude pre-release tags in GitCommitChecker

## v0.69.33, 5 September 2018

- Python: Don't parse dependencies that won't be updated in FileUpdater

## v0.69.32, 5 September 2018

- Truncate long commit message subject lines
- Make Python label colour less ugly

## v0.69.31, 5 September 2018

- Use source API endpoint in labeler
- Bump poetry from 0.11.4 to 0.11.5

## v0.69.30, 4 September 2018

- Docker: Store tag when parsing Dockerfile
- Docker: Update source tag in UpdateChecker
- Docker: Do file updating based on changes to requirement sources

## v0.69.29, 4 September 2018

- Elixir: Handle multiline declarations that need to be updated
- Ruby: Handle gemspec updates when Gemfile has now default source

## v0.69.28, 4 September 2018

- Ruby: Handle JFrog permissions error

## v0.69.27, 4 September 2018

- Terraform: Swap error class

## v0.69.26, 4 September 2018

- Terraform: Raise resolvability error for invalid registry sources

## v0.69.25, 4 September 2018

- JS: Look for path dependencies that start with "/", too
- JS: Parse file dependencies that start with a '/' as file dependencies

## v0.69.24, 4 September 2018

- JS: Fetch / create path dependencies that don't prefix 'file:'

## v0.69.23, 4 September 2018

- Ruby: Upgrade list of known rubies, and raise if unsatisfied

## v0.69.22, 3 September 2018

- Update DockerRegistry client, and use new digest method
- Docker: Update digest logic
- Docker: Handle digest-only updates in PR creator

## v0.69.21, 3 September 2018

- Python: Handle hash versions in FileParser

## v0.69.20, 3 September 2018

- Python: Update requirements.txt if it is an output from Pipenv

## v0.69.19, 3 September 2018

- Python: Parse Pipfiles without a Pipfile.lock
- Python: Parse dependencies from multiple sources
- Python: Allow Pipfile without Pipfile.lock in FileFetcher and FileParser
- Python: Handle Pipfiles without a Pipfile.lock in FileUpdater
- Python: Firm up logic around resolution manager selection in UpdateChecker
- Python: Firm up logic around resolution manager selection in FileUpdater
- Python: Add test for FileUpdater with only a Pipfile

## v0.69.18, 2 September 2018

- Rust: Fetch rust-toolchain file if present
- Rust: Write rust-toolchain before shelling out to cargo

## v0.69.17, 2 September 2018

- Python: Don't double-wrap git credentials

## v0.69.16, 2 September 2018

- Python: Catch bad reference errors and raise them as such
- Python: Raise a GitDependenciesNotReachable error for unreachable Pipfile deps

## v0.69.15, 2 September 2018

- Python: Set git credentials before resolving Pipfiles

## v0.69.14, 2 September 2018

- Python: Handle edited Pipfile.lock in file preparer

## v0.69.13, 2 September 2018

- Python: Handle Pipfile.lock with string versions
- Add files ending in tfvars to updated_files_regex

## v0.69.12, 1 September 2018

- Terraform: Handle Terragrunt files, too

## v0.69.11, 1 September 2018

- Java: Handle properties with numeric components more sensitively

## v0.69.10, 31 August 2018

- Docker: Consider tags of latest version when determining if release is a pre

## v0.69.9, 31 August 2018

- PHP: Ignore errors that happened during lockfile generation, as long as
  lockfile generated successfully

## v0.69.8, 30 August 2018

- Python: Appease pip-tools, and spec that requirements are included
- Python: Remove pbr requirement

## v0.69.7, 30 August 2018

- Python: Add pbr as a requirement

## v0.69.6, 30 August 2018

- Python: Sanitize setup.cfg, too

## v0.69.5, 30 August 2018

- JS: Bump npm from 6.4.0 to 6.4.1
- Python: Fetch setup.cfg if present
- Python: Check whether setup.py is using pbr
- Python: Handle setup.py files that use a __name__ == '__main__' structure

## v0.69.4, 29 August 2018

- Java: Handle hard requirements

## v0.69.3, 29 August 2018

- Java: Extend requirement class to understand range requirements

## v0.69.2, 27 August 2018

- PHP: Better handling of git sources

## v0.69.1, 27 August 2018

- Java: Handle bad GitHub URLs in POMs
- Handle changelog headers that start with ==

## v0.69.0, 27 August 2018

- Rename bump_versions_if_needed to bump_versions_if_necessary

## v0.68.8, 25 August 2018

- Pass preview header when creating dependencies label

## v0.68.7, 25 August 2018

- Terraform: Add proper requirements updater class. that ensures `~> ...`
  requirements are updated properly
- Terraform: Add version and requirement classes to preserve pre-release
  formatting

## v0.68.6, 24 August 2018

- Python: Sanitize setup.py for use with Pipenv

## v0.68.5, 24 August 2018

- Terraform: Handle registry dependencies in update checker

## v0.68.4, 23 August 2018

- Terraform: Handle config files with a duplicated git source

## v0.68.3, 23 August 2018

- Terraform: Return Gem::Version objects from latest_version, not strings

## v0.68.2, 23 August 2018

- Terraform: Parse version out of git reference

## v0.68.1, 23 August 2018

- Terraform: Test requirements_unlocked_or_can_be? method (and fix it!)

## v0.68.0, 23 August 2018

- Terraform: Initial support

## v0.67.8, 22 August 2018

- Python: Handle unmet markers in a pip-compile requirements file

## v0.67.7, 22 August 2018

- Ruby: Handle out-of-sync git version for dependency

## v0.67.6, 22 August 2018

- Docker: Handle non-existant directories

## v0.67.5, 21 August 2018

- Elm: Update version finder to handle new Elm website (now with JSON API!)

## v0.67.4, 21 August 2018

- JS: Add InconsistentRegistryResponse error, and raise it when npm can't yet
  use latest release

## v0.67.3, 21 August 2018

- JS: Handle empty package-lock.json when updating a git dependency

## v0.67.2, 21 August 2018

- Docker: Fetch custom named files (as long as they contain "dockerfile")
- Docker: Handle parsing multiple files in FileParser
- Docker: Update multiple files at once in FileUpdater
- Docker: Handle requirement changing in some files but not all

## v0.67.1, 21 August 2018

- Docker: Parse multiple identical FROM lines in a Dockerfile as a single
  dependency

## v0.67.0, 21 August 2018

- Ruby: Bump Bundler to 1.16.4. This is considered a BREAKING change as you will
  need to update the Bundler version in whatever environment you run Dependabot
  in

## v0.66.29, 20 August 2018

- Docker: Raise PrivateSourceAuthenticationFailure error for private registies
  on dockerhub

## v0.66.28, 20 August 2018

- Make dependencies label regex looser
- JS: Nicer JS label colour

## v0.66.27, 20 August 2018

- Ruby: Sanitize gemspecs more thoroughly

## v0.66.26, 19 August 2018

- .NET: Handle csproj PackageReference lines that specify an Update, not an
  Include
- Ruby: Less ugly label colour

## v0.66.25, 18 August 2018

- Add option to label language when creating PRs

## v0.66.24, 18 August 2018

- Java: Better repo lookup (handle monorepos much better)

## v0.66.23, 17 August 2018

- Label PRs with major, minor and patch if those labels exist

## v0.66.22, 17 August 2018

- JS: Handle path dependencies specified by workspace packages

## v0.66.21, 17 August 2018

- Ruby: Ignore timeouts from Rubygems
- Python: Handle empty versions (convert them to 0)

## v0.66.20, 17 August 2018

- Escape issue number references prefixed with a backslash
- PHP: Upgrade Composer to 1.7.2
- JS: Retry more timeouts if Yarn resolution fails

## v0.66.19, 16 August 2018

- Ignore existing dependency labels that contain a slash when checking for
  default

## v0.66.18, 16 August 2018

- Symbolise requirements_update_strategy before passing to RequirementsUpdater

## v0.66.17, 15 August 2018

- JS: Minimal sanitization of package.json content everywhere, with tests

## v0.66.16, 15 August 2018

- JS: Minimal sanitization of package.json content
- Python: Detect poetry libraries
- Python: Parse private poetry sources properly
- Python: Always bump the version of Poetry dev dependencies
- Python: Add poetry definition for production deps

## v0.66.15, 15 August 2018

- Java: Handle timeouts when looking up metadata
- Python: Handle Poetry requirements better

## v0.66.14, 14 August 2018

- .NET: Handle wildcard versions

## v0.66.13, 14 August 2018

- Bump groovy-all from 2.5.0 to 2.5.2
- Accept a custom branch name separator
- Python: Handle || requirements (used in Poetry)

## v0.66.12, 14 August 2018

- Python: Add poetry files to rebase triggereing regexes

## v0.66.11, 14 August 2018

- Revert "Fix flaky spec using SharedHelpers.in_a_temporary_directory"

## v0.66.10, 14 August 2018

- Python: Handle pyproject.toml requirement updates
- Python: Handle ~ and ^ requirements (for poetry)
- JS: Improve caret version handling

## v0.66.9, 14 August 2018

- Python: Handle unparseable pipfile when fetching indexes
- Ruby: Don't raise error if locking Ruby version to one in gemspec causes
  problems
- Python: Rescue JSON::ParserError, not JSON::ParseError

## v0.66.8, 13 August 2018

- Python: Fix missing method

## v0.66.7, 13 August 2018

- Python: Add initial support for Poetry

## v0.66.6, 12 August 2018

- Go: Make requirement update style configurable

## v0.66.5, 10 August 2018

- Rust: Better support for glob workspace declarations

## v0.66.4, 10 August 2018

- Ruby: Fix requirement replacer when no previous requirement is passed

## v0.66.3, 10 August 2018

- Ruby: Maintain whitespace before comments in Gemfile / gemspec

## v0.66.2, 10 August 2018

- Python: Handle subdependencies in PipfileVersionResolver

## v0.66.1, 9 August 2018

- Add requirements_update_strategy option to UpdateChecker, and use it to
  determine how to update JS requirements

## v0.66.0, 9 August 2018

- BREAKING: Pass target branch via source, rather than as a separate option,
  when passing it to PullRequestCreator

## v0.65.0, 9 August 2018

- Better directory lookup in Dependabot::Source
- BREAKING: Pass target branch via source, rather than as a separate option,
  when passing it to FileFetcher

## v0.64.17, 8 August 2018

- Python: Raise DependencyFileNotParseable error for unparseable Pipfiles

## v0.64.16, 8 August 2018

- Ruby: Don't accidentally unlock other top-level dependencies in FileUpdater
- JS: Don't raise a resolvability error if package.json is currently resolvable
- PHP: Bump composer/composer from 1.7.0 to 1.7.1

## v0.64.15, 7 August 2018

- Add milestones to PRs if requested

## v0.64.14, 6 August 2018

- Ruby: Handle git sources that multiple dependencies use

## v0.64.13, 6 August 2018

- Ruby: Reject dependencies that don't update in ForceUpdater

## v0.64.12, 6 August 2018

- Ruby: Use (simple) custom unlocking logic in UpdateChecker

## v0.64.11, 6 August 2018

- Ruby: Handle another category of yanked subdependencies

## v0.64.10, 6 August 2018

- Ruby: Patch Bundler to avoid mutating conflict trees

## v0.64.9, 6 August 2018

- PHP: Always write PHP errors on shotdown

## v0.64.8, 6 August 2018

- PHP: Better error text for composer plugic clashes

## v0.64.7, 6 August 2018

- PHP: Handle incompatible flex versions

## v0.64.6, 5 August 2018

- PHP: Bump Composer to 1.7.0

## v0.64.5, 5 August 2018

- .NET: Use v2 API for look up latest version when required

## v0.64.4, 5 August 2018

- .NET: Ignore v2 package APIs for now

## v0.64.3, 4 August 2018

- Elm: Don't update groups to nil

## v0.64.2, 4 August 2018

- Elm: Return an empty array for groups, not nil

## v0.64.1, 4 August 2018

- Elm: Fix file fetcher method dependence

## v0.64.0, 4 August 2018

- Elm: Initial support (v0.18 only)

## v0.63.29, 2 August 2018

- Ruby: Unlock all subdependencies when checking for resolvability

## v0.63.28, 2 August 2018

- JS: Prioritise getting version for package.json's requirement

## v0.63.27, 2 August 2018

- JS: Handle subdependencies that import a git dependency properly
- Add PHP extensions to dockerfile
- Refactor JS file udpaters into separate classes
- Bump npm from 6.2.0 to 6.3.0

## v0.63.26, 1 August 2018

- Ruby: Handle custom default sources correctly in LatestVersionFinder

## v0.63.25, 1 August 2018

- Ruby: Handle updates blocked by a subdependency in the FileUpdater

## v0.63.24, 1 August 2018

- Maven: Use packaging type 'pom' for parent nodes

## v0.63.23, 31 July 2018

- JS: Handle git:// dependencies that upgrade across versions

## v0.63.22, 31 July 2018

- JS: Raise error if no files change in FileUpdater

## v0.63.21, 31 July 2018

- Elixir: Handle projects without a mix.lock

## v0.63.20, 30 July 2018

- Rust: Update feature build-dependencies

## v0.63.19, 30 July 2018

- Maven: Raise DependencyFileNotFound for missing modules

## v0.63.18, 30 July 2018

- JS: Back to Yarn 1.9.2 (now fixed!)

## v0.63.17, 30 July 2018

- JS: Revert Yarn upgrade, until https://github.com/yarnpkg/yarn/issues/6174
  is fixed or handled

## v0.63.16, 29 July 2018

- Python: Fetch all .txt and .in files and check if they're requirement files,
  as well as all .txt and .in files nested one repo deeper

## v0.63.15, 29 July 2018

- Go: Use go-get=1 trick to find git source URLs for unrecognised names

## v0.63.14, 29 July 2018

- Go: Ignore constraints for dependencies that don't appear in the lockfile
- JS: Update npm sub-dependencies

## v0.63.13, 29 July 2018

- Go: Handle projects that import themselves in their main.go

## v0.63.12, 28 July 2018

- Maven: Don't fetch child poms stored in submodules (we can't update them)

## v0.63.11, 28 July 2018

- Maven: Handle submodules when fetching files

## v0.63.10, 28 July 2018

- Maven: Fix release checking so it actually checks the file type

## v0.63.9, 28 July 2018

- JS: Change library behaviour back for repos without a lockfile

## v0.63.8, 27 July 2018

- Go: Use GOPATHs in temp dirs when shelling out to dep

## v0.63.7, 27 July 2018

- Go: Make updated version format match original format when using tags

## v0.63.6, 26 July 2018

- Go: Don't parse version as a requirement for git dependencies

## v0.63.5, 26 July 2018

- Go: Protect against nil `latest_resolvable_version` (for previous rubygems
  version)
- Go: Handle dependencies that specify a tag as a version

## v0.63.4, 26 July 2018

- JS: Handle substring git reference versions
- Gradle: Silence persistent bug (replace with pending spec)

## v0.63.3, 26 July 2018

- Go: Raise Dependabot::GitDependenciesNotReachable error for unreachable git
  dependencies

## v0.63.2, 26 July 2018

- Go: Better library detection (pull down all top-level Go files)

## v0.63.1, 26 July 2018

- Go: Update app requirements differently to library requirements

## v0.63.0, 26 July 2018

- Elixir: Use Elixir v1.7.0 (which includes hex resolver changes)
- Go: Make use of new information in dep v0.5.0 lockfiles, if available
- Go: Update dep behaviour to work with dep v0.5.0 (i.e., create digests)

## v0.62.5, 25 July 2018

- Go: Fix file update generation for branches

## v0.62.4, 25 July 2018

- Go: Don't try to lock revision for branch updates

## v0.62.3, 25 July 2018

- Go: Don't import internal packages

## v0.62.2, 25 July 2018

- Go: Import all packages that were used in lockfile
- Go: Handle git dependencies correctly in metadata finder

## v0.62.1, 25 July 2018

- Go: Import packages, not projects

## v0.62.0, 25 July 2018

- Go: Initial support (no vendoring, library-style manifest updates)

## v0.61.99, 25 July 2018

- Ruby: Handle "." paths in the lockfile

## v0.61.98, 24 July 2018

- Rust: Fix path dependency sanitization in FileUpdater

## v0.61.97, 23 July 2018

- Fetch more files on GitLab

## v0.61.96, 23 July 2018

- Rust: Better handling of workspace errors

## v0.61.95, 23 July 2018

- JS: Handle git dependencies with auth details embedded in URL
- Rust: Don't update versions in path dependencies

## v0.61.94, 20 July 2018

- Ruby: Don't error for outdated lockfile git dependencies

## v0.61.93, 20 July 2018

- Ruby: Preserve non-standard ordering of git dependencies in lockfile

## v0.61.92, 20 July 2018

- JS: More sophisticated handling of globs when considering workspaces / Lerna
  files

## v0.61.91, 20 July 2018

- JS: Handle path expansion of multiple asterisks

## v0.61.90, 20 July 2018

- JS: Store version as git SHA for git dependencies using Yarn
- JS: Fall back to  when an updated version can't be found

## v0.61.89, 20 July 2018

- Gradle: Handle dependencies that aren't listed in Google's repository

## v0.61.88, 20 July 2018

- Python: Raise a resolvability error if original Pipfile can't be resolved

## v0.61.87, 19 July 2018

- JS: Better handling of lerna requirements in FileUpdater

## v0.61.86, 19 July 2018

- JS: Add details of the file that was being updated when an error occurred

## v0.61.85, 19 July 2018

- Ruby: Special case handling of Bundler in UpdateCheckers::LatestVersionFinder

## v0.61.84, 18 July 2018

- JS: Overwrite npm's checkPlatform method

## v0.61.83, 18 July 2018

- Ruby: Set git credentials before trying to find latest version of git
  dependency

## v0.61.82, 18 July 2018

- JS: Ignore aliased dependencies (for now)

## v0.61.81, 18 July 2018

- .NET: Handle directory deletions in FileFetcher

## v0.61.80, 17 July 2018

- .NET: Handle updates for imported property files properly

## v0.61.79, 17 July 2018

- Ruby: Don't artificially insert Bundler version in FileParser

## v0.61.78, 17 July 2018

- Handle rare case where filtering releases yields an empty array
- Fetch 100 last releases in MetadataFinder, not 30

## v0.61.77, 17 July 2018

- JS: Don't try to update workspace packages

## v0.61.76, 17 July 2018

- JS: Don't double-fetch path dependencies
- Fix blank line after truncated vulnerability details text
- Ruby: Use Bundler 1.16.3

## v0.61.75, 16 July 2018

- JS: Ignore bad npm responses for git dependencies

## v0.61.74, 16 July 2018

- Handle commit messages where the entire message is just a linebreak!

## v0.61.73, 16 July 2018

- Handle commit messages that start with a linebreak

## v0.61.72, 14 July 2018

- PHP: Handle 403s in FileUpdater
- JS: Handle missing package errors better
- JS: Raise DependencyFileNotEvaluatable for workspace errors

## v0.61.71, 14 July 2018

- Dockerfile: Switch to gnupg2
- JS: Bump npm

## v0.61.70, 13 July 2018

- Python: Allow single component versions with a pre-release

## v0.61.69, 13 July 2018

- JS: Treat temporary npm 500 as a 404

## v0.61.68, 13 July 2018

- Ruby: Handle rubygems server timeouts in MetadataFinder

## v0.61.67, 13 July 2018

- Python: Handle whitespace in pip compile requirements
- Ruby: Automatically retry some Bundler errors
- Dockerfile: Use Ubuntu 18.04

## v0.61.66, 12 July 2018

- Ruby: Fix inconsistency between UpdateChecker and FileUpdater that caused rare
  bug

## v0.61.65, 11 July 2018

- JS: Handle 405s from registry when checking git dependencies

## v0.61.64, 11 July 2018

- JS: Relax requirement that all workspaces specified in package.json are
  fetchable

## v0.61.63, 11 July 2018

- JS: Better handling of Lerna lockfiles (not all will need to be updated)

## v0.61.62, 10 July 2018

- JS: Add support for Lerna. Dependabot will now pull down your lerna.json file,
  parse it, and pull down all of the relevant packages for your project.
  Dependabot PRs for repos using Lerna will update all of your packages at once
  (if you'd prefer to receive a single PR per packages you can manually add each
  package as a separate directory in Dependabot).

## v0.61.61, 10 July 2018

- JS: Exclude prereleases of next version when building ruby req of caret
  requirement

## v0.61.60, 09 July 2018

- JS: Parse Yarn lockfiles to build path dependencies, too

## v0.61.59, 09 July 2018

- Ruby: Don't try to rescue using a string
- JS: Build an imitation path dependency package.json when required

## v0.61.58, 08 July 2018

- PHP: Handle empty lockfiles

## v0.61.57, 06 July 2018

- Don't misinterpret GitHub downtime as repos being more generally unreachable

## v0.61.56, 05 July 2018

- Rust: Fetch path dependencies for target-specific deps

## v0.61.55, 05 July 2018

- Python: Handle errors installing futures on Python 3

## v0.61.54, 05 July 2018

- Rust: Better file updating of feature dependencies (handle repeated case
  properly)
- Gradle: Correct caching of properties in FileParser

## v0.61.53, 05 July 2018

- Python: Handle requirement.txt dependency reqs that are a substring of another
  requirement
- Python: Handle pip-compile dependency requirements that are a substring of
  another requirement

## v0.61.52, 04 July 2018

- .NET: Handle PackageReference lines without a version requirement

## v0.61.51, 02 July 2018

- Rust: Handle updating multiple requirements in a single manifest file

## v0.61.50, 02 July 2018

- PHP: Don't error when updating subdependencies that are no longer required

## v0.61.49, 02 July 2018

- JS: Handle environment variables in npmrc URLs

## v0.61.48, 02 July 2018

- JS: Catch more git authentication / repo not found errors

## v0.61.47, 01 July 2018

- Python: Update Pipenv to 2018.7.1

## v0.61.46, 29 June 2018

- Python: More Pipenv woe. Revert version further (oops!)

## v0.61.45, 29 June 2018

- Python: Revert Pipenv version again :-(

## v0.61.44, 29 June 2018

- Rust: Handle yanked Rust versions in FileUpdater
- Elixir: more aggressive timeout handling
- Move git config logic into SharedHelpers
- Update Dockerfile for new PHP extension

## v0.61.43, 29 June 2018

- Fix git credential reset logic

## v0.61.42, 29 June 2018

- Update semantic-release commit messages to be compliant with
  @commitlint/config-conventional

## v0.61.41, 28 June 2018

- PHP: Handle composer.json files that ask for non-existant path dependency
  repos but don't need them

## v0.61.40, 28 June 2018

- JS: Handle case where a subdependency introduces a git requirement

## v0.61.39, 28 June 2018

- .NET: Fetch ProjectReference files

## v0.61.38, 27 June 2018

- Python: Handle another form of Python 2.7 resolvability issue

## v0.61.37, 27 June 2018

- JS: Retry registry errors during yarn.lock update

## v0.61.36, 27 June 2018

- JS: Retry npm registry errors in VersionResolver

## v0.61.35, 27 June 2018

- Update GitLab default API endpoint to remove trailing slash
- Use source api endpoint in gitlab client for using self host gitlab
- JS: Set git credentials when switching from ssh to ssl in FileUpdater

## v0.61.34, 26 June 2018

- Python: Bump Pipenv version back to 2018.6.25 (with some special handling)
- Python: Use Python 2.7.15 instead of 2.7.14

## v0.61.33, 26 June 2018

- Python: Revert back to Pipenv 2018.5.18

## v0.61.32, 26 June 2018

- Label security fix PRs with a security label

## v0.61.31, 26 June 2018

- Handle changelogs with comparison links in their headers
- Add custom labels to PR as long as some exist

## v0.61.30, 25 June 2018

- Handle private GitLab sources in CommitsFinder

## v0.61.29, 25 June 2018

- Python: Use latest pipenv
- Maven: Find nested plugin dependency declarations

## v0.61.28, 25 June 2018

- PHP: Set git credentials when doing Composer updates (to handle no-api
  updates)

## v0.61.27, 25 June 2018

- PHP: Don't remove no-api settings from composer.json in FileUpdater

## v0.61.26, 24 June 2018

- PHP: Use GitHub API when resolving versions

## v0.61.25, 22 June 2018

- Add scope to semantic commit messages

## v0.61.24, 22 June 2018

- Better handling of monorepo tags
- JS: Replace all git url config when initially setting

## v0.61.23, 22 June 2018

- PHP: Switch ssh git URLs to use ssl instead
- JS: Clean up gitconfig changes even if error occurs

## v0.61.22, 22 June 2018

- JS: Handle more git URL types

## v0.61.21, 22 June 2018

- Add another PHP extension to dockerfile
- Clean up git config after Rust update checks
- JS: Fix FileUpdater for SSH URLs by setting git config

## v0.61.20, 22 June 2018

- Raise internal error if npm updates can't reach an ssh URL

## v0.61.19, 21 June 2018

- .NET: Keep track of the files we've fetched better (avoids duplicate requests)

## v0.61.18, 21 June 2018

- .NET: Allow repos with just a .sln file at the top level
- Ruby: More specific check for private registries
- Elixir: Pin erlang version in Dockerfile

## v0.61.17, 21 June 2018

- .NET: Ignore failed imports (until we handle properties we can't rely on the
  paths)

## v0.61.16, 21 June 2018

- .NET: Fetch project files referenced in .sln files

## v0.61.15, 21 June 2018

- Ruby: Retry more errors in FileUpdater
- .NET: Handle capitalisation of packages.config file
- .NET: Handle more dependency file names when considering rebasing

## v0.61.14, 20 June 2018

- Python: Fix requirement filtering when using pip-compile with uncompiled files

## v0.61.13, 19 June 2018

- .NET: Handle packages.config files in FileUpdater
- .NET: Add parser for packages.config dependencies

## v0.61.12, 19 June 2018

- .NET: Use credentials provided to access private repositories
- .NET: Fetch credentials from nuget.config file, too, if present
- .NET: Raise PrivateSourceAuthenticationFailure when auth fails for custom
  repos

## v0.61.11, 19 June 2018

- .NET: Set repo details as source in UpdateChecker (for use later in
  MetadataFinder)
- .NET: Use dependency source in MetadataFinder if present
- Java: Handle java-specific versions in Utils::Java::Requirement class

## v0.61.10, 18 June 2018

- .NET: Handle custom repositories (without auth details)

## v0.61.9, 18 June 2018

- Rust: Preserve pre-release formatting in Utils::Rust::Requirement

## v0.61.8, 17 June 2018

- Dotnet: First version of support for NuGet

## v0.61.7, 15 June 2018

- PHP: Handle OR requirements in new version_from_requirements check

## v0.61.6, 15 June 2018

- Improve issue tag sanitization

## v0.61.5, 15 June 2018

- Rust: Better detection of lowest version in requirement
- Rust: Handle latest_allowable_versions that are lower than the current version
- All: Add check that new version is greater than permitted by old requirements

## v0.61.4, 15 June 2018

- Python: Handle version ranges separted by commas in Python::Requirement
- PHP: Handle unparseable composer.json files

## v0.61.3, 14 June 2018

- JS: Avoid downloading huge version arrays when possible

## v0.61.2, 13 June 2018

- Rust: Ensure manifest-only setups don't downgrade

## v0.61.1, 13 June 2018

- Handle Requests changelog version underline character
- Ruby: Handle invalid Ruby in FileFetcher

## v0.61.0, 12 June 2018

- BREAKING: Rename PrivateSourceNotReachable to
  PrivateSourceAuthenticationFailure (since we now have PrivateSourceTimedOut)
- Docker: Permit non-standard registries without credentials
- Refactor specs

## v0.60.8, 12 June 2018

- Rust: Check for latest allowable version in UpdateChecker

## v0.60.7, 11 June 2018

- Elixir: Revert "Remove unused subdependencies after update"

## v0.60.6, 11 June 2018

- Elixir: Handle git dependencies in umbrella apps correctly

## v0.60.5, 11 June 2018

- Elixir: Remove unused subdependencies after update

## v0.60.4, 10 June 2018

- Ruby: Ignore bad responses when checking Ruby version compatibility

## v0.60.3, 10 June 2018

- First version of GitLab PR creator. This library can now be used to
  dependabot-script to create PRs on GitLab

## v0.60.2, 09 June 2018

- Add logging for strange type error
- Add GitLab support to PullRequestCreator::MessageBuilder
- Split GitHub logic out of PullRequestUpdater (turns out to be all of it!)
- Ruby: Handle timeouts when checking if Ruby version is incompatible
- PHP: Include additional extension in Dockerfile (ext-intl)

## v0.60.1, 08 June 2018

- Handle timeouts in Ruby metadata finder
- Add timeout defaults to all Excon calls

## v0.60.0, 08 June 2018

- PHP: Respect platform requirements if they are set
- Update groovy to 2.5.0, and add PHP extensions to Dockerfile

## v0.59.53, 07 June 2018

- JS: Better ignore of package-lock.json if asked to in .npmrc

## v0.59.52, 07 June 2018

- Ignore unprocessible entity errors when adding labels (work around GitHub bug)

## v0.59.51, 06 June 2018

- JS: Better sanitization of package.json in FileParser
- JS: Handle npm lockfiles with missing version information

## v0.59.50, 06 June 2018

- JS: Better caching in UpdateChecker
- JS: Handle package.json files with escaped whitespace

## v0.59.49, 06 June 2018

- Python: Bug fix - don't double-update compiled requirement files

## v0.59.48, 06 June 2018

- Python: Handle uncompiled requirement files in PipCompileFileUpdater

## v0.59.47, 06 June 2018

- Python: Resolve pip-compile sub-dependencies in the context of their compile
  files in UpdateChecker

## v0.59.46, 05 June 2018

- Python: Include requirements.txt requirement in parsed req if no pip-compile
  file
- Python: Handle sub-dependency updates within a pip-compile setup

## v0.59.45, 05 June 2018

- Python: Pull private sources out of Pipfiles for quicker update checking
- Python: Don't try to handle pip-compile subdependencies
- Python: Use requirements.txt updater in FileUpdater if sub-dep

## v0.59.44, 05 June 2018

- Python: Handle updating dependencies for which we can't find a latest version

## v0.59.43, 05 June 2018

- Python: Select resolution type based on dependency requirements, not files

## v0.59.42, 05 June 2018

- Maven: Handle versions without numbers in RequirementsUpdater

## v0.59.41, 05 June 2018

- JS: Better timeout error handling

## v0.59.40, 05 June 2018

- JS: Add timeout logic to version resolver
- JS: Raise PrivateSourceNotReachable error when a private source times out

## v0.59.39, 04 June 2018

- Rust: Handle blank requirements in FileParser

## v0.59.38, 04 June 2018

- Rust: Convert ssh URLs to https in UpdateChecker
- Rust: Handle ssh git dependencies in FileUpdater

## v0.59.37, 04 June 2018

- JS: Handle empty package-lock.json files

## v0.59.36, 04 June 2018

- JS: Fix replaceDeclaration function, and test that it works for tricky case

## v0.59.35, 04 June 2018

- Ignore failure to add team collaborators to PRs
- Maven: Handle versions that start non-numeric

## v0.59.34, 02 June 2018

- Maven: Check for a jar on repository before selecting a version

## v0.59.33, 02 June 2018

- Handle unlikely case of release without a tag name

## v0.59.32, 31 May 2018

- Gradle: Handle ignored versions
- Maven: Consider type suffix when determining version to update to
- Maven: Handle credential URLs with login details in UpdateChecker

## v0.59.31, 30 May 2018

- PHP: Fix bug in subdependency updates

## v0.59.30, 29 May 2018

- Elixir: Update to specific version in FileUpdater

## v0.59.29, 29 May 2018

- JS: Handle another npm error type

## v0.59.28, 29 May 2018

- Elixir: Consider ignore requirements when determining latest resolvable
  version
- Improve FilePreparer to lookup existing version from requirements

## v0.59.27, 29 May 2018

- JS: Handle git reference errors in FileUpdater

## v0.59.26, 29 May 2018

- Fall back to GitHub git data API for large files

## v0.59.25, 28 May 2018

- Elixir: Consider ignore conditions when determining latest version
- PHP: Catch out of memory errors in FileUpdater

## v0.59.24, 28 May 2018

- Python: Raise a DependencyFileNotEvaluatable for impossible requirements

## v0.59.23, 28 May 2018

- Maven: Continue processing if only some dependencies use inaccessible
  properties

## v0.59.22, 28 May 2018

- Maven: Clearer error message when property can't be found

## v0.59.21, 28 May 2018

- Ruby: Consider ignored versions when determining latest resolvable version.
  This might sound innocuous but it's a significant improvement over previous
  behaviour: if a user chooses to ignore Rails 5, for example, they'll now
  continue to receive updates to Rails 4 if/when they're released. Bring Ruby
  support in-line with Python, PHP, Java and JS, where this is already offered.

## v0.59.20, 28 May 2018

- Java: More careful updating for property versions
- Ruby: Update to the version given in FileUpdater (don't just unlock)
- Ruby: Include upper bound in FilePreparer if given a latest_allowable_version

## v0.59.19, 26 May 2018

- Python: Preserve custom headers in pip-compile generated files
- Update rubygems and add libmysqlclient-dev to dockerfile
- Better version string sanitization for presentation of vulnerabilities

## v0.59.18, 26 May 2018

- PHP: Only catch out of memory errors in shutdown handler

## v0.59.17, 25 May 2018

- JS: Consider ignored versions when determining version to update to
- JS: Update FileUpdater to install a specific version

## v0.59.16, 25 May 2018

- PHP: Ignore ignored versions when checking latest version
- PHP: Consider ignored versions when determining version to update to
- PHP: Update to the specific version given in dependency.version in FileUpdater

## v0.59.15, 24 May 2018

- JS: Raise unhandled error if FileUpdater fails to find the version we're
  updating to

## v0.59.14, 24 May 2018

- PHP: Unlock subdependencies when updating top-level ones

## v0.59.13, 24 May 2018

- JS: Tailor authentication type for global registry based on credentials

## v0.59.12, 24 May 2018

- Maven: Handle multiple identical declarations
- JS: Use npm 6.1.0

## v0.59.11, 24 May 2018

- Gradle: Fix property updater
- Maven: Fix single-dependency property updating, and make RequirementsUpdater
  clearer

## v0.59.10, 24 May 2018

- Maven: Handle updating a dependency that is managed by multiple properties

## v0.59.9, 24 May 2018

- Maven: Preserve base directory when updating a property value

## v0.59.8, 24 May 2018

- Maven: Make DeclarationFinder more discerning (don't confuse property versions
  with straight declarations)

## v0.59.7, 24 May 2018

- Python: Add full stops to name sanitization regex in UpdateChecker

## v0.59.6, 23 May 2018

- Ruby: Retry version resolution if a private source may be to blame for a resolvability error
- Ruby: Remove unnecessary RuntimeError handling

## v0.59.5, 23 May 2018

- JS: More robust lookup of global registry

## v0.59.4, 23 May 2018

- JS: Add workaround for Yarn workspaces bug

## v0.59.3, 23 May 2018

- Ruby: Switch back to just using lockfile path dependencies if a lockfile is
  present (otherwise conditionals in the lockfile can cause problems)

## v0.59.2, 22 May 2018

- Python: Consider ignored versions when determining updates for pip-compile
  setups

## v0.59.1, 22 May 2018

- Better presentation of vulnerability details in PR description

## v0.59.0, 22 May 2018

- BREAKING Python: Use Python 2.7 with pip-compile if required
- Ruby: Augment lockfile path dependencies with gemfile ones

## v0.58.35, 22 May 2018

- JS: Handle 5xx responses from registry more gracefully in MetadataFinder
- JS: Handle timeouts from the registry more gracefully

## v0.58.34, 21 May 2018

- Ruby: Handle cases where only pre-release versions exist

## v0.58.33, 21 May 2018

- Identify changelogs headers underlined with ====

## v0.58.32, 21 May 2018

- Ruby: Consider ignored versions when determining latest version
- Python: Consider ignore conditions when calculating latest resolvable version
  for Pipfile

## v0.58.31, 21 May 2018

- Python: Consider ignored versions in UpdateChecker

## v0.58.30, 21 May 2018

- Maven: Raise a DependencyFileNotParseable error for missing properties

## v0.58.29, 21 May 2018

- Handle git URLs that already have credentials in GitCommitChecker

## v0.58.28, 21 May 2018

- Python: Unlock dependencies with non-normalised names correctly

## v0.58.27, 21 May 2018

- Python: Handle multiple-requirements that get reordered during file parsing

## v0.58.26, 20 May 2018

- Don't duplicate headers in release notes (check for them in release body)

## v0.58.25, 20 May 2018

- Use emoji in PR title for gitmoji commits
- Java (Maven and Gradle): Use short name for Java PRs

## v0.58.24, 19 May 2018

- Python: Handle non-unlocking case properly

## v0.58.23, 19 May 2018

- Python: Keep existing options when updating a requirements.txt file generated
  by pip-compile

## v0.58.22, 18 May 2018

- Handle switches from numeric to git sources (happens when lockfile is
  out-of-date)

## v0.58.21, 18 May 2018

- Python: Unlock bounds in pip-config files when necessary to update

## v0.58.20, 18 May 2018

- Python: Use normalised dependency names (rather than using the unnormalised
  name)

## v0.58.19, 18 May 2018

- Python: Add support for pip-compile files (i.e., `requirements.in` and
  friends). Initial support is very rough.

## v0.58.18, 18 May 2018

- JS: Handle "402: Payment required" responses from npmjs

## v0.58.17, 17 May 2018

- If token is likely to be Basic auth, use Basic auth

## v0.58.16, 17 May 2018

- Remove any "\n" characters from generated Basic auth tokens

## v0.58.15, 17 May 2018

- Elixir: Handle regex versions in FileParser

## v0.58.14, 17 May 2018

- Test against updated Elixir, Rust and Bundler
- Fix Bundler 1.16.2 change and remove redundant Rust tests
- Add test for JRuby support

## v0.58.13, 16 May 2018

- Maven: Exclude ignored versions when looking for version to update to

## v0.58.12, 15 May 2018

- Java (Maven & Gradle): Better metadata lookup (check parent for GitHub URLs)

## v0.58.11, 15 May 2018

- Maven: Support custom maven_repositories passed as credentials

## v0.58.10, 15 May 2018

- PHP: Handle dependencies replaced in composer.json

## v0.58.9, 15 May 2018

- Rust: Raise resolvability error if the lockfile can't be parsed

## v0.58.8, 15 May 2018

- Rust: Ensure correct versions are installed in FileUpdater by temporarily
  specifying them in the Cargo.toml

## v0.58.7, 14 May 2018

- Use gitmoji commit messages if repo uses them (thanks @mockersf)
- Rust: Update git tags if they look like versions

## v0.58.6, 14 May 2018

- Ruby: Rescue from unevaluatable gemspecs

## v0.58.5, 14 May 2018

- Ruby: Better gemspec filename lookup
- Rust: Add basic git dependency handling to FileUpdater
- Rust: Add basic git dependency handling to UpdateChecker
- Ruby: Use fetch when getting host from credentials

## v0.58.4, 14 May 2018

- Filter credentials on type everywhere

## v0.58.3, 14 May 2018

- JS: Handle socket errors when looking for registries
- Rust: Handle git dependencies in version resolver
- Rust: Add support for getting latest version of git dependencies

## v0.58.2, 13 May 2018

- Expect git_source credentials to have a username and password (not a token)
- Add tests that all requests to the public GitHub instance can handle not
  having credentials (since they may not do for Enterprise installs)

## v0.58.1, 13 May 2018

- Fix Dependabot::Source error when a string hostname was provided

## v0.58.0, 13 May 2018

- BREAKING: Require a type attribute for git source credentials
- BREAKING: Require a hostname when specifying an api_endpoint for a
            Dependabot::Source
- PHP: Set credentials for all known git sources (means private Bitbucket and
  Gitlab repos are now supported)
- Rust: Set credentials for all known git sources (means private Bitbucket and
  Gitlab repos are now supported)

## v0.57.0, 12 May 2018

- BREAKING: Expect a Dependabot::Source object as a FileFetcher argument
- BREAKING: Require Dependabot::Source to be passed to FileParsers
  (not repo string)
- BREAKING: Require Dependabot::Source as an argument to PR creator and updater
- Python: Bump pipenv from 11.10.4 to 2018.5.18
- Allow Dependabot::Source objects to be created with a custom API endpoint

## v0.56.34, 12 May 2018

- Make GitCommitChecker agnostic between GitHub, Gitlab and Bitbucket

## v0.56.33, 11 May 2018

- Use Bitbucket credentials in metadata lookup if present

## v0.56.32, 11 May 2018

- Ruby: Handle version assignment to a variable in gemspec sanitizer

## v0.56.31, 11 May 2018

- Prioritize longer credentials when looking for a match
- Handle redirects from http to https more robustly by excluding the default
  port

## v0.56.30, 11 May 2018

- Check if credentials have a host before trying to match on it

## v0.56.29, 11 May 2018

- Stop relying on being passed a credential type

## v0.56.28, 11 May 2018

- Update GitCommitChecker to auth with non-GitHub sources

## v0.56.27, 10 May 2018

- Support adding assignees to PRs

## v0.56.26, 10 May 2018

- Python: Handle arbitrary equality matcher

## v0.56.25, 10 May 2018

- PHP: Better handling of PHP plugins (don't disable them all)

## v0.56.24, 10 May 2018

- PHP: Disable plugins during install

## v0.56.23, 10 May 2018

- JS: Correct handling of Yarn workspaces specified with an object

## v0.56.22, 10 May 2018

- JS: Handle Yarn workspace specification that uses objects instead of arrays

## v0.56.21, 10 May 2018

- Handle reviewers hashes (rather than arrays)
- JS: Bump npm to 6.0.1

## v0.56.20, 09 May 2018

- Support a `reviewers` option when creating PRs

## v0.56.19, 09 May 2018

- PHP: Add support for path based dependencies

## v0.56.18, 08 May 2018

- Gradle: More accurate dependency parser
- Gradle: Ignore InnerClassNodes during parsing

## v0.56.17, 08 May 2018

- JS: Switch SSH for SSL in package-lock.json file updater

## v0.56.16, 08 May 2018

- Ruby: Don't include temporary path details in issue text
- JS: Switch ssh git URLs for https during resolution

## v0.56.15, 08 May 2018

- Rust: Set global credentials helper, with file in temporary directory

## v0.56.14, 08 May 2018

- Rust: Back to local config (init git repo first)

## v0.56.13, 08 May 2018

- Rust: Set global, not local, credentials helper

## v0.56.12, 08 May 2018

- Rust: Set GitHub credentials when doing update runs

## v0.56.11, 07 May 2018

- JS: Raise resolvability error for npm lockfiles which can't be resolved
- Python: Allow retries in Pipenv

## v0.56.10, 07 May 2018

- Python: Bump Pipenv to 11.10.2

## v0.56.9, 07 May 2018

- JS: Fix conversion of `*` requirement

## v0.56.8, 07 May 2018

- Handle Gradle projects with sub-projects

## v0.56.7, 05 May 2018

- Don't attempt to sanitize mentions with a / in them (they're scopes!)

## v0.56.6, 05 May 2018

- Python: Quietly ignore error when updating to a new version that has a bad
  setup.py
- Python: Bump Pipenv commit

## v0.56.5, 05 May 2018

- Gradle: Special case Google version lookup
- Python: Handle spaces before method calls
- JS: Retry calls to registry if they timeout

## v0.56.4, 04 May 2018

- Gradle: Handle custom repositories

## v0.56.3, 04 May 2018

- Gradle: Handle buildfiles with import statements
- Gradle: Upgrade groovy-all version
- Gradle: Better error messages when parsing fails

## v0.56.2, 04 May 2018

- Gradle: Fix helper path

## v0.56.1, 04 May 2018

- PHP: Bump Composer version

## v0.56.0, 04 May 2018

- BREAKING: Use Groovy to parse Gradle files. Please update the container you
  run dependabot-core in to have Groovy available (e.g., use the latest
  dependabot/dependabot-core container).
- Gradle: Handle property version updates

## v0.55.22, 03 May 2018

- Python: Improve error message when Pipfile can't be resolved

## v0.55.21, 03 May 2018

- Python: Raise error for unresolvable Pipfiles

## v0.55.20, 03 May 2018

- Ruby: Restrict force updates to pareto improvements

## v0.55.19, 03 May 2018

- Ruby: Fix typo
- Create directory structure in temporary directories if required

## v0.55.18, 02 May 2018

- Ruby: Allow Gemfiles and gemspecs to include files with require_relative

## v0.55.17, 02 May 2018

- Sanitize branch names that would include dot-directories

## v0.55.16, 02 May 2018

- Ruby: Don't exclude updated dependencies from force updater

## v0.55.15, 02 May 2018

- Ruby: Raise error for unfetchable gemspec paths

## v0.55.14, 02 May 2018

- Elixir: Move requirements array logic into requirements class
- PHP: Better requirement updating (preserve dev branches in or requirements)

## v0.55.13, 02 May 2018

- Bump pipenv version
- JS: Handle `~>` requirement matcher (treat as `~`, rather than as Ruby `~>`)

## v0.55.12, 02 May 2018

- Java: Initial Gradle support (very basic)

## v0.55.11, 01 May 2018

- Handle very bad changelog encodings
- Python: More robust handling of bad index page responses

## v0.55.10, 01 May 2018

- Python: Handle bad URLs in metadata lookup

## v0.55.9, 30 April 2018

- JS: Don't jump across pre-release versions

## v0.55.8, 30 April 2018

- JS: Ignore deprecated versions when looking for source URL

## v0.55.7, 30 April 2018

- JS: Exclude deprecated versions when looking for updates

## v0.55.6, 30 April 2018

- Python: Handle version freezing for dependencies with extras more carefully

## v0.55.5, 30 April 2018

- Python: Use keep-outdated as well as freezing

## v0.55.4, 30 April 2018

- Python: Freeze dependencies manually, rather than with keep-outdated

## v0.55.3, 30 April 2018

- Python: Source repo finding improvements

## v0.55.2, 29 April 2018

- Clearer links to changelogs / release notes
- Minor improvement to changelog parsing
- Java: Look everywhere in the POM for a GitHub URL

## v0.55.1, 29 April 2018

- Python: Looks at package homepage if URL can't be found in PyPI data
- Update PyPI URL for Warehouse

## v0.55.0, 29 April 2018

- BREAKING: Use pyenv to manage Python version. This requires an update to the
  setup you use to run Dependabot Core - see the updated Dockerfile (basically
  you have to have pyenv installed)

## v0.54.69, 27 April 2018

- Python: Write all dependency files when generating a new Pipfile.lock
- Python: Handle logging in setup.py (who would do that?!?)

## v0.54.68, 27 April 2018

- PHP: Handle errors caused by new npm-signature downloader type

## v0.54.67, 27 April 2018

- Python: Upgrade Pipenv to 11.10.1. Fixes some parser errors.

## v0.54.66, 26 April 2018

- Ruby: Update all ssh URLs to use HTTPS

## v0.54.65, 26 April 2018

- Python: Scrub updated source details from lockfile
- Python: Raise DependencyFileNotParseable for TOML that Pipenv can't handle

## v0.54.64, 26 April 2018

- Java: Find property versions in profile properties
- Java: Handle inaccessible repositories in UpdateChecker

## v0.54.63, 25 April 2018

- Java: Ignore repositories that aren't URLs

## v0.54.62, 25 April 2018

- Java: More robust file fetching

## v0.54.61, 25 April 2018

- Python: Handle private indexes timing out for requirements.txt dependencies

## v0.54.60, 25 April 2018

- Python: Raise PrivateSourceNotReachable errors for Pipfile sources that can't
  be reached

## v0.54.59, 25 April 2018

- Ignore changelogs which don't contain any relevant versions
- Reject blank tags / names during release finder lookup

## v0.54.58, 25 April 2018

- Python: Handle html index responses in MetadataFinder

## v0.54.57, 25 April 2018

- Java: Handle updates where the dependency appears multiple times, and one case
  is already up-to-date

## v0.54.56, 24 April 2018

- JS: Use npm6 when end-user repository is

## v0.54.55, 24 April 2018

- Java: Handle repeated dependencies in FileUpdater robustly

## v0.54.54, 24 April 2018

- Python: Raise PrivateSourceNotReachable for Pipfiles with environment
  variables but no config

## v0.54.53, 24 April 2018

- Python: Handle private registries in MetadataFinder

## v0.54.52, 24 April 2018

- Python: Handle private sources in Pipfile

## v0.54.51, 24 April 2018

- Java: Download parent POMs, when present, to allow property evaluation

## v0.54.50, 24 April 2018

- Python: Better error for requirement files that use an unrecognised option

## v0.54.49, 23 April 2018

- Java: Fix PropertyUpdater bug caused by incorrect declaration requirement
  selection

## v0.54.48, 23 April 2018

- Ruby: Update gemspec to latest resolvable version if using equality matcher

## v0.54.47, 23 April 2018

- JavaScript: Return the latest pre-release if it is specified in a latest tag
  and the user wants prereleases

## v0.54.46, 23 April 2018

- Java: Handle extensions in FileUpdater

## v0.54.45, 23 April 2018

- Java: Stricter property finding (tighter XPaths)
- Java: Evaluate properties whenever values are taken from POM

## v0.54.44, 23 April 2018

- Allow metadata key in dependency requirements
- Java: Store property name when parsing dependencies
- Java: Use stored property name everywhere

## v0.54.43, 23 April 2018

- Java: Fix typo in PropertyUpdater

## v0.54.42, 23 April 2018

- Java: Better title for multi-dependency PRs
- Java: Cache DeclarationFinder in FileUpdater to avoid repeated calls to
  repositories
- Java: Use Java DeclarationFinder to get property name consistently everywhere

## v0.54.41, 23 April 2018

- Java: Handle cases where parent POMs can't be fetched

## v0.54.40, 22 April 2018

- Java: Check custom repositories when lookin for property declarations

## v0.54.39, 22 April 2018

- Java: Handle custom repositories in MetadataFinder

## v0.54.38, 22 April 2018

- Java: Better MetadataFinder CSS paths
- Java: Support use of custom repositories in UpdateChecker
- Java: Use main registry URL directly, not search API
- Java: Add commments for FileParser, and add extensions to list of updatable
  dependencies
- Elixir: Clean up requirement class

## v0.54.37, 21 April 2018

- Java: Add requirements_unlocked_or_can_be? method to UpdateChecker
- Java: Remove duplicated code between PropertyValueFinder and
  PropertyValueUpdater

## v0.54.36, 21 April 2018

- Java: Encode Maven URLs correctly in UpdateChecker and MetadataFinder
- Java: Handle remote parent poms in FileParser (will need work in
  UpdateChecker)

## v0.54.35, 21 April 2018

- Java: Fix error message when a property can't be found

## v0.54.34, 20 April 2018

- Java: Handle multimodule projects in FileFetcher, FileParser, UpdateChecker
  and FileUpdater

## v0.54.33, 19 April 2018

- JS: Don't truncate pre-release versions in RequirementsUpdater

## v0.54.32, 19 April 2018

- Ruby: Ignore gemspec versions specified with a constant

## v0.54.31, 19 April 2018

- Ruby: Handle projects that import multiple top-level dependencies

## v0.54.30, 19 April 2018

- Handle nil tag names in ReleaseFinder
- Move GemspecDependencyNameFinder namespace to FileUpdaters

## v0.54.29, 18 April 2018

- Elixir: Ignore irrelevant Elixir warnings

## v0.54.28, 18 April 2018

- Ruby: Better sanitization of path gemspecs

## v0.54.27, 18 April 2018

- Ruby: Don't fetch contents for repos nested in submodules

## v0.54.26, 18 April 2018

- Ruby: Handle submodule path dependencies

## v0.54.25, 18 April 2018

- Java: Handle whitespace in pom.xml declarations

## v0.54.24, 18 April 2018

- Accommodate difficult tag names in ReleaseFinder

## v0.54.23, 17 April 2018

- Java: Implement Java version comparison based on Maven spec

## v0.54.22, 17 April 2018

- Rust: Check for latest version differently when updating sub-dependencies

## v0.54.21, 17 April 2018

- Elixir: Add support for private repos
- Ruby: Less opinionated update for equality matchers in gemspecs

## v0.54.20, 17 April 2018

- Ruby: Require a latest_resolvable_version to update gemspec requirements

## v0.54.19, 16 April 2018

- Ruby: More robust ruby requirement parsing

## v0.54.18, 16 April 2018

- Java: Filter out date-based release numbers if that's not what's currently
  being used
- Java: Handle dependencies with multiple declarations in FileParser and
  UpdateChecker

## v0.54.17, 16 April 2018

- Ruby: Handle resolution error caused by Ruby's CompactIndex ocassionally
  being unavailable

## v0.54.16, 16 April 2018

- Ruby: Cleaner path dependency fetching

## v0.54.15, 16 April 2018

- Handle overflowing tables when truncating pull request details

## v0.54.14, 16 April 2018

- Ruby: Handle file updates where the declaration is in an evaled Gemfile
- Move Dependabot::MetadataFinders::Base::Source to Dependabot::Source

## v0.54.13, 15 April 2018

- Python: Silence error output in Python file updater

## v0.54.12, 15 April 2018

- JS: Refactor UpdateChecker
- JS: Bump Yarn to 1.6.0

## v0.54.11, 14 April 2018

- JS: Update Yarn resolutions when updating a dependency that specifies them

## v0.54.10, 14 April 2018

- JS: Handle version requirements with a `v` prefix
- Python: Bump pip from 10.0.0.0b2 to 10.0.0

## v0.54.9, 14 April 2018

- Java: Handle POM updates where the file uses a property with a suffix

## v0.54.8, 14 April 2018

- Rust: Fix regex for updating feature dependencies
- JS: Handle package.json declarations with whitespace before the colon
- PHP: Handle composer.json declarations with whitespace before the colon

## v0.54.7, 13 April 2018

- Python: Ignore specified Python versions in Pipfile during file updating, too

## v0.54.6, 13 April 2018

- Python: Ignore specified Python versions in Pipfile (best we can do for now)

## v0.54.5, 13 April 2018

- Ruby: Augment private gemserver info with Rubygems details if appropriate

## v0.54.4, 13 April 2018

- Ruby: Handle Bundler::PathError in update checker

## v0.54.3, 13 April 2018

- Python: Reject `nil` values from version resolver
- Python: Write setup.py when resolving a Pipfile
- Python: Further fix for path dependency handling with Pipfile
- Handle nested Ruby path dependencies

## v0.54.2, 12 April 2018

- Python: Bump pip to 10.0.0.0b2

## v0.54.1, 12 April 2018

- Python: Add version resovler for Pipenv

## v0.54.0, 12 April 2018

- BREAKING: Pass credentials to PullRequestCreator and PullRequestUpdater
  instead of a client

## v0.53.38, 12 April 2018

- Ruby: Test that auth details are passed to gem server in MetadataFinder
- Ruby: Treat private rubygems sources more like default sources in
  MetadataFinder

## v0.53.37, 12 April 2018

- JS: Handle JavaScript::Version being created with a version class
  (not a string)
- Java: Cache latest version in update checker

## v0.53.36, 12 April 2018

- JS: Handle versions prefixed with a v in utils classes

## v0.53.35, 11 April 2018

- Ruby: Fetch changelogs for private source dependencies

## v0.53.34, 11 April 2018

- JS: Better sanitization of npmrc files

## v0.53.33, 11 April 2018

- JS: Filter out nil requirements in update checker (when updating git
  dependencies)

## v0.53.32, 11 April 2018

- Implement Requirement.requirements_array for all languages

## v0.53.31, 11 April 2018

- Ruby: Prepare files to ensure only updates are possible

## v0.53.30, 10 April 2018

- Python: Handle empty version strings in Utils::Python::Version
- PHP: Handle array entries for "extra" in composer.lock

## v0.53.29, 9 April 2018

- Rust: Handle old-format lockfiles

## v0.53.28, 9 April 2018

- PHP: Add patches back to lockfile after update (if required)

## v0.53.27, 9 April 2018

- Handle badly named releases

## v0.53.26, 9 April 2018

- Better release note filtering (will mean release notes are included in PRs
  even if the latest version doesn't have any)

## v0.53.25, 9 April 2018

- Look at release tag_name before looking at release name

## v0.53.24, 9 April 2018

- Update Elixir and PHP versions
- PHP: Raise Dependabot::DependencyFileNotResolvable error for invalid version
  constraints

## v0.53.23, 6 April 2018

- Rust: Handle feature dependencies that have a feature removed in the new
  version

## v0.53.22, 6 April 2018

- Elixir: Ignore dependency updates that would cause diverging environment
  requirements

## v0.53.21, 6 April 2018

- Ruby: Even more gemspec sanitization (this time for splatted requirements)

## v0.53.20, 6 April 2018

- Ruby: Ignore requirements specified with a ternary operator and an expression

## v0.53.19, 6 April 2018

- Include previous release notes in PR if valuable, even if the latest version
  doesn't have any (but previous versions do)

## v0.53.18, 5 April 2018

- PHP: Ensure version requirements don't decrease, and refactor UpdateChecker

## v0.53.17, 5 April 2018

- Ruby: Fix gemspec version sanitization from string versions

## v0.53.16, 5 April 2018

- Ruby: More aggressive gemspec sanitization

## v0.53.15, 5 April 2018

- Rust: Handle dependencies with multiple versions properly in UpdateChecker

## v0.53.14, 5 April 2018

- PHP: Handle branch names with a number in them

## v0.53.13, 5 April 2018

- Rust: Ignore patched dependencies (for now)

## v0.53.12, 5 April 2018

- JS: Handle non-existant dependencies

## v0.53.11, 5 April 2018

- PHP: Add hack for updating composer.json correctly

## v0.53.10, 4 April 2018

- Fix GitHub file contents error that was being caused by mutated arguments

## v0.53.9, 4 April 2018

- Ruby: Use source of dependency from lockfile and Gemfile combined in
  UpdateChecker

## v0.53.8, 4 April 2018

- PHP: Use vcs repository types, not git ones

## v0.53.7, 3 April 2018

- Python: Handle odd Python requirements
- Ruby: Fall back to lockfile if no source information in Gemfile

## v0.53.6, 3 April 2018

- Show vulnerability version range depending on kind of range passed

## v0.53.5, 3 April 2018

- Handle comma separated requirement strings in Utils::Php::Requirement

## v0.53.4, 2 April 2018

- Create Utils::Ruby::Requirement class

## v0.53.3, 2 April 2018

- Truncate long vulnerability descriptions
- Include source details for security vulnerabilities

## v0.53.2, 2 April 2018

- Add [security] prefix to PR names for PRs that fix vulnerabilities

## v0.53.1, 2 April 2018

- Display vulnerability details in PR text if passed them

## v0.53.0, 2 April 2018

- BREAKING: Move Version and Requirement classes into Utils namespace

## v0.52.30, 1 April 2018

- Add convenience methods for accessing version and requirement classes

## v0.52.29, 31 March 2018

- Rust: Target latest version, not latest resolvable version, for libraries

## v0.52.28, 31 March 2018

- Rust: Handle repos without a lockfile in UpdateCheckers::VersionResolver

## v0.52.27, 31 March 2018

- Ruby: Sanitize gemspec using GemspecSanitizer class everywhere

## v0.52.26, 31 March 2018

- Ruby: Sanitize require_relative lines from gemspec

## v0.52.25, 31 March 2018

- Rust: Handle feature dependencies

## v0.52.24, 31 March 2018

- Rust: Add resolvability check to UpdateChecker

## v0.52.23, 30 March 2018

- JS: Handle registry timeouts when looking through private registries

## v0.52.22, 30 March 2018

- Rust: Use --aggressive update if conservative one fails

## v0.52.21, 30 March 2018

- Rust: Handle projects that use workspaces

## v0.52.20, 29 March 2018

- Rust: Handle multi-version dependencies in FileUpdater
- Rust: Add support for workspaces to FileFetcher

## v0.52.19, 29 March 2018

- JS: Use package-lockfile-only option
- Add workaround for npm git dependency issues

## v0.52.18, 29 March 2018

- More logging for strange GitHub array error

## v0.52.17, 29 March 2018

- Rust: More specs, and error if no files are updated in FileUpdater

## v0.52.16, 29 March 2018

- Rust: Raise errors when file updating fails

## v0.52.15, 29 March 2018

- Rust: Drop use of --precise when updating files

## v0.52.14, 29 March 2018

- Rust: Get relevant versions in FileParser when there are multiple available

## v0.52.13, 28 March 2018

- Ruby: Always include pre-release details in requirement if updating to one

## v0.52.12, 28 March 2018

- Ruby: Handle the prerelease part of versions separately when updating
  requirements

## v0.52.11, 28 March 2018

- JS: Fix scoped registry URL

## v0.52.10, 28 March 2018

- JS: Scope private registries to the scoped packages they're intended for

## v0.52.9, 28 March 2018

- JS: Avoid yarn bug by always authing when Basic credentials are present

## v0.52.8, 28 March 2018

- JS: Handle Basic auth in FileUpdater

## v0.52.7, 28 March 2018

- JS: Use Basic auth to get latest version when appropriate

## v0.52.6, 28 March 2018

- JS: Include global auth token when building a global registry npmrc

## v0.52.5, 28 March 2018

- JS: Fix typo

## v0.52.4, 28 March 2018

- JS: Use lockfile to build .npmrc file, if required and not committed

## v0.52.3, 28 March 2018

- JS: Rely on RegistryFinder for constructing all dependency URLs

## v0.52.2, 28 March 2018

- Rust: Add support for Cargo.toml files with path dependencies

## v0.52.1, 28 March 2018

- JS: Fix bug in git dependency handling
- Rust: Only try to update lockfile if we were given one to start with

## v0.52.0, 27 March 2018

- First version of Rust support

## v0.51.20, 25 March 2018

- Ruby: Handle yanked dependencies

## v0.51.19, 24 March 2018

- Handle GitHub contents error in MetadataFinder

## v0.51.18, 24 March 2018

- JS: Use npm 5.8.0

## v0.51.17, 23 March 2018

- JS: Don't try to downgrade requirement files that have pinned to a
  post-latest version

## v0.51.16, 23 March 2018

- Docker: Move digest fetching to UpdateChecker

## v0.51.15, 23 March 2018

- Docker: Handle file updates where a tag and digest have been specified

## v0.51.14, 23 March 2018

- Fix encoding error when fetching changelogs

## v0.51.13, 23 March 2018

- Ruby: Don't try to replace requirement if using a ternary operator

## v0.51.12, 22 March 2018

- Return subdependencies from JS FileParsers (imperfectly)

## v0.51.11, 22 March 2018

- Fix typo

## v0.51.10, 22 March 2018

- Allow punctuation after GitHub issue / PR numbers when creating links
- JS: Refactor registry lookup into separate class
- JS: Split library detection out of UpdateChecker

## v0.51.9, 22 March 2018

- JS: Handle private sources when we don't have a lockfile

## v0.51.8, 22 March 2018

- Java: Handle property version suffixes in update checker

## v0.51.7, 22 March 2018

- Java: Handle versions that come partially from a property

## v0.51.6, 22 March 2018

- Sanitize GitHub links

## v0.51.5, 22 March 2018

- Raise BranchNotFound error when getting a branch's head commit fails

## v0.51.4, 21 March 2018

- Automatically retry strange GitHub error

## v0.51.3, 21 March 2018

- Handle null bodies in release notes

## v0.51.2, 20 March 2018

- Ruby: More robust requirements_unlocked_or_can_be? implementation

## v0.51.1, 20 March 2018

- JS: Handle git dependencies that have never been released

## v0.51.0, 20 March 2018

- JS: Update from git commit refs/branches to released versions

## v0.50.56, 20 March 2018

- Add UpdateCheckers#requirements_unlocked_or_can_be? method

## v0.50.55, 19 March 2018

- Retry Octokit::BadGateway errors

## v0.50.54, 19 March 2018

- Don't pull down changelogs over 1mb

## v0.50.53, 19 March 2018

- Add newline after changelog truncation

## v0.50.52, 19 March 2018

- Update git dependencies that specify a reference along with a full URL

## v0.50.51, 19 March 2018

- Return `false` early in UpdateCheckers#can_update? when checking whether a
  library can be updated without unlocking its requirements

## v0.50.50, 18 March 2018

- PHP: Only fetch composer URLs when looking for registry details

## v0.50.49, 18 March 2018

- PHP: Handle unexpected data from private registries

## v0.50.48, 18 March 2018

- Python: Use pip 9.0.2
- Ruby: Update commit SHAs should come from tag (because that's what Gemfile
  stores)

## v0.50.47, 16 March 2018

- PHP: Spec private registry behaviour, and add better error messages for it

## v0.50.46, 16 March 2018

- PHP: Fix PHP Updater bug (oops!)

## v0.50.45, 16 March 2018

- PHP: Pass registry credentials to Composer

## v0.50.44, 16 March 2018

- Rescue all commit URL NotFound errors
- JS: Cache updated requirements in UpdateChecker

## v0.50.43, 15 March 2018

- Java: Handle non-numeric versions
- Ignore lost races when creating PRs

## v0.50.42, 15 March 2018

- Add logging for rare GitHub error

## v0.50.41, 15 March 2018

- Handle commit diffs with no common ancestor

## v0.50.40, 14 March 2018

- Reverse commits order (most recent first)
- Better changelog importing when changelog is appended at bottom
- Bump pipenv from 11.7.4 to 11.8.0

## v0.50.39, 14 March 2018

- Link tags in changelogs correctly

## v0.50.38, 14 March 2018

- Include upgrade guide in dependency tabs
- Sanitize template tags in changelogs

## v0.50.37, 14 March 2018

- Better changelog intro text
- Better display of SHA version is PRs
- Use 7 digits for SHA branch names, not 6
- Fix broken method name

## v0.50.36, 14 March 2018

- Fall back to tag name in ReleaseFinder#releases_text

## v0.50.35, 14 March 2018

- Better release note parsing for PRs
- Use Pipenv 11.7.1

## v0.50.34, 14 March 2018

- Fix release sorting

## v0.50.33, 14 March 2018

- More robust PR message builder
- Truncate long changelogs
- Add fullstop to changelog source line
- Better release sorting
- More robust changelog sorting

## v0.50.32, 14 March 2018

- Better changelog line detection

## v0.50.31, 14 March 2018

- Fix encoding bug during PR creation
- Better referencing of changelog source

## v0.50.30, 14 March 2018

- Pull changelogs into PR descriptions

## v0.50.29, 13 March 2018

- Java: Fix Java argument in UpdateChecker

## v0.50.28, 13 March 2018

- Java: Ignore versions that can't be matched

## v0.50.27, 13 March 2018

- Java: Better POM property substitution in MetadataFinder

## v0.50.26, 13 March 2018

- Escape @mentions in PR body

## v0.50.25, 13 March 2018

- JS: Only de-dop the dependency we're updating
- Ruby: Update commit SHAs should come from commit, not tag

## v0.50.24, 13 March 2018

- Better commits view for pull requests
- Add embedded release notes to PRs

## v0.50.23, 12 March 2018

- Never return nil from CommitsFinder#commits
- Add release_text method to ReleaseFinder

## v0.50.22, 12 March 2018

- Use details tab for commit details, if they're all we're including in PR

## v0.50.21, 12 March 2018

- Elixir: Use commit SHA, not tag SHA, when updating git references

## v0.50.20, 12 March 2018

- Fix handling of git commit tags (non-semver)

## v0.50.19, 12 March 2018

- Python: only do Pipfile file updates if a lockfile is also present
- Java: Find property-based dependencies in branch namer correctly

## v0.50.18, 12 March 2018

- Handle Elixir dependencies without a requirement in UpdateChecker
- Automatically retry GitHub 500s
- Python: Use Pipenv 11.5.2

## v0.50.17, 11 March 2018

- Elixir: Don't change lockfile format during update
- Python: Use Pipenv 11.3.3

## v0.50.16, 11 March 2018

- Allow hyphens in git tags and refs

## v0.50.15, 11 March 2018

- Elixir: Add support for updating pinned git dependencies

## v0.50.14, 10 March 2018

- Add specs for Elixir FilePreparer (and fix a bug)

## v0.50.13, 10 March 2018

- Downgrade Pipenv to 11.1.11
- Refactor Elixir UpdateChecker (should be no noticeable change to ens-users)

## v0.50.12, 10 March 2018

- Elixir: Update to pre-release versions if the user is already on one (or has
  specified a pre-release in their requirements)

## v0.50.11, 10 March 2018

- Elixir: Add support for git-source dependencies

## v0.50.10, 9 March 2018

- Java: Handle multiple declarations of same dependency in pom.xml

## v0.50.9, 9 March 2018

- Java: Handle source URLs which use a property

## v0.50.8, 9 March 2018

- Don't try to create branches with spaces in them

## v0.50.7, 9 March 2018

- Python: Parse requirements.txt if a Pipfile with no Pipfile.lock is present

## v0.50.6, 9 March 2018

- Submodules: Use default branch, not master, if no branch is specified

## v0.50.5, 8 March 2018

- PHP: Handle version requirements with a commit SHA in them

## v0.50.4, 8 March 2018

- Python: Fix declaration regex in FileUpdater for dependencies with a hyphen

## v0.50.3, 8 March 2018

- Add upgrade guide link to PRs, if present and upgrading by a major version

## v0.50.2, 8 March 2018

- JS: Check for path dependencies in lockfile as well as package.json

## v0.50.1, 8 March 2018

- JS: Exclude file based dependencies where the file details are in the version
  (not the requirement)

## v0.50.0, 8 March 2018

- BREAKING: Remove "pipfile" package manager entirely. It is now bundler under
  "pip", which will autodetect whether a Pipfile is being used.

## v0.49.16, 8 March 2018

- Python: Combine python strategies. Non-breaking, as long as you weren't
  accessing the Pipfile classes directly.

## v0.49.15, 7 March 2018

- Ruby: Handle ~> ranges with major precision

## v0.49.14, 7 March 2018

- Fix dependency file uniqueness checking (fixes a rare bug in Ruby updates)
- Use GithubClientWithRetries everywhere

## v0.49.13, 7 March 2018

- Automatically retry GitHub timeouts during file fetching

## v0.49.12, 6 March 2018

- JS: Less aggressive yarn.lock deduping

## v0.49.11, 6 March 2018

- Retry rare Ruby bug in commit signer

## v0.49.10, 6 March 2018

- Don't mistake commit messages that just start with Fix for semantic commit
  messages

## v0.49.9, 5 March 2018

- Add #production? method to Dependabot::Dependency instances

## v0.49.8, 5 March 2018

- PHP: Better regex for git clone problems

## v0.49.7, 5 March 2018

- PHP: Handle dependency reachability errors in FileUpdater

## v0.49.6, 5 March 2018

- Elixir: Handle references specified as a charlist

## v0.49.5, 4 March 2018

- Handle inconsistent responses from github whengetting a ref

## v0.49.4, 4 March 2018

- Handle superstring branches when creating PRs

## v0.49.3, 3 March 2018

- Handle PR creation when a branch exists but a PR doesn't

## v0.49.2, 2 March 2018

- Elixir: Support for git dependencies in FileParser and MetadataFinder.

## v0.49.1, 2 March 2018

- Elixir: Handle very old lockfiles

## v0.49.0, 2 March 2018

- Elixir: Full support for umbrella apps 🎉

## v0.48.20, 2 March 2018

- Python: Better pre-release handling
- Elixir: Lots of prep for umbrella apps (but not full support yet)

## v0.48.19, 1 March 2018

- Better changelog finding (order by file size if multiple with same name)

## v0.48.18, 1 March 2018

- Python: Normalise pre-release versions correctly

## v0.48.17, 1 March 2018

- Include signoff line in commit messages

## v0.48.16, 1 March 2018

- JS: Handle exact matches for libraries

## v0.48.15, 1 March 2018

- Python: Fix typo that prevented dev package updates
- JS: Handle lockfiles with bad version (wrong source)

## v0.48.14, 28 February 2018

- PHP: Handle empty array returned from packagist in MetadataFinder

## v0.48.13, 28 February 2018

- PHP: Include subdependencies in parser output
- Python: Use Pipenv's new --keep-outdated option insted of freezing Pipfile

## v0.48.12, 27 February 2018

- Python: Pipfile file parser now include subdependencies in results

## v0.48.11, 27 February 2018

- JS: Use Yarn v1.5.0

## v0.48.10, 27 February 2018

- Pipfile: include dependencies specified using a requirements hash

## v0.48.9, 26 February 2018

- Add label description if creating a new dependencies label

## v0.48.8, 26 February 2018

- Java: Don't propose updates to a prerelease unless desired

## v0.48.7, 26 February 2018

- PHP: Retry timeouts in UpdateChecker
- PHP: Handle array errors in ExceptionIO

## v0.48.6, 26 February 2018

- JS: Handle yarn lockfiles that are missing a requirement in their declaration
  lines

## v0.48.5, 26 February 2018

- Ignore bash scripts when looking for changelog

## v0.48.4, 25 February 2018

- JS: Handle lockfiles without a header in fix-duplicates

## v0.48.3, 25 February 2018

- Elixir: Remove hex install in Elixir file parser
- JS: Vendor relevant yarn-tools code (so they can be edited)
- JS: Don't lose Yarn version info during de-duping

## v0.48.2, 25 February 2018

- JS: Use yarn-tools to clean up yarn.lock after updates

## v0.48.1, 25 February 2018

- Python: Only include Pipfile in updated files if it has changed
- JS: Handle updates that don't change the package.json better

## v0.48.0, 23 February 2018

- Add option to sign commits

## v0.47.15, 22 February 2018

- JS: Fix encoding bug

## v0.47.14, 21 February 2018

- JS: Don't check npm for package.json files with no description

## v0.47.13, 21 February 2018

- JS: Better detection of whether a project is an app or a library

## v0.47.12, 21 February 2018

- Bump pipenv from 9.0.3 to 9.1.0 in /helpers/python

## v0.47.11, 20 February 2018

- Look for changelog in the directory we have for a repo

## v0.47.10, 20 February 2018

- Include target branch in branch name if present

## v0.47.9, 20 February 2018

- Check for existing PRs before assuming the presence of a branch means there's
  no need to create one

## v0.47.8, 19 February 2018

- Ruby: Add specs for UpdateCheckers#latest_resolvable_version_with_no_unlock
  and fix implementation
- Elixir: Spec UpdateCheckers#latest_resolvable_version_with_no_unlock

## v0.47.7, 17 February 2018

- Java: Shorter branch names when updating multiple dependencies

## v0.47.6, 17 February 2018

- Java: Handle versionless declaration nodes in PropertyUpdater

## v0.47.5, 16 February 2018

- Java: Handle property updates in a single PR (rather than creating several)

## v0.47.4, 16 February 2018

- JS: Fix parser for dependencies with a resolutions entry

## v0.47.3, 16 February 2018

- JS: Handle authentication errors from npm5 (not just Yarn)

## v0.47.2, 16 February 2018

- Require Ruby 2.5

## v0.47.1, 15 February 2018

- Correct semantic commit casing for library updates
- Include directory details in library PRs
- JS: Ignore 404s from the registry for library dependencies

## v0.47.0, 15 February 2018

- BREAKING: Pass `requirements_to_unlock` to UpdateCheckers#can_update? and
  UpdateCheckers#updated_dependencies instead of `unlock_level`

## v0.46.6, 12 February 2018

- JS: Handle blank requirements

## v0.46.5, 12 February 2018

- Python: Ignore Pipfile dependencies missing from the lockfile

## v0.46.4, 12 February 2018

- Use Angular style sentence case if using semantic commits

## v0.46.3, 9 February 2018

- Exclude bot commits when considering recent commit messages. Should ensure
  switchover to semantic commit messages happens faster

## v0.46.2, 9 February 2018

- PHP: Handle packagist returning empty arrays

## v0.46.1, 9 February 2018

- Allow `no_requirements` to be passed to UpdateCheckers#can_update? and
  UpdateCheckers#updated_dependencies as an unlock level

## v0.46.0, 9 February 2018

- BREAKING: Pass `unlock_level` to UpdateCheckers#can_update? and
  UpdateCheckers#updated_dependencies
- Add a latest_resolvable_version_with_no_unlock method to the UpdateChecker
  for each language

## v0.45.5, 7 February 2018

- Add GitLab support to FileFetcher base methods
- Support GitLab in submodules FileFetcher. All FileFetchers therefor now
  support GitLab

## v0.45.4, 6 February 2018

- JS: Handle unreachable git dependencies better (and spec it!)

## v0.45.3, 5 February 2018

- JS: Ignore path dependency package.json files when parsing

## v0.45.2, 5 February 2018

- Ruby: Update to newer pre-release versions
- JS: Raise GitDependenciesNotReachable error for git dependencies we don't
  have access to

## v0.45.1, 30 January 2018

- Elixir: Handle mix.exs files that load in a version file

## v0.45.0, 30 January 2018

- Ruby: Include sub-dependencies in FileParser#parse result

## v0.44.20, 30 January 2018

- PHP: Handle aliased requirements in UpdateChecker (update the real version)

## v0.44.19, 30 January 2018

- Elixir: Perform hex install in pwd

## v0.44.18, 28 January 2018

- PHP: Filter out special packages

## v0.44.17, 27 January 2018

- Java: Handle dependencies that use the project version as their requirement
- Ruby: Raise error for merge conflicts in Gemfile.lock

## v0.44.16, 26 January 2018

- PHP: Handle repos where the only version is non-numeric

## v0.44.15, 26 January 2018

- PHP: Handle alias version constraints

## v0.44.14, 25 January 2018

- Java: Handle nested dependency declarations in pom.xml

## v0.44.13, 24 January 2018

- Ruby: Use Lockfile to find path dependencies if present

## v0.44.12, 23 January 2018

- Java: Ignore plugins without a groupId

## v0.44.11, 23 January 2018

- Use `build` prefix if semantic commits are in use

## v0.44.10, 23 January 2018

- Elixir: Clean up Ruby code that calls Elixir subprocesses

## v0.44.9, 23 January 2018

- Handle timeouts in GitCommitChecker

## v0.44.8, 23 January 2018

- Ruby: Handle timeouts when checking whether git dependencies are reachable

## v0.44.7, 22 January 2018

- PHP: Retry 404s which appear to be happening randomly

## v0.44.6, 22 January 2018

- Silence errors when trying to update a PR that has been merged

## v0.44.5, 22 January 2018

- Elixir: Wait for input (should fix Errno::EPIPE errors)

## v0.44.4, 21 January 2018

- PHP: Use env-key instead for env_key (for consistency with Python)

## v0.44.3, 21 January 2018

- PHP: Raise MissingEnvironmentVariable instead of PrivateSourceNotReachable

## v0.44.2, 21 January 2018

- PHP: Allow environment variables to be passed (to support ACF PRO)

## v0.44.1, 20 January 2018

- Fix PullRequestCreator behaviour when no dependencies tag exists

## v0.44.0, 20 January 2018

- Pass an array of custom labels to PullRequestCreator

## v0.43.11, 20 January 2018

- Elixir: Raise a DependencyFileNotResolvable error if mix.exs contains bad
  requirements

## v0.43.10, 19 January 2018

- Java: Fix version parsing (oops!)

## v0.43.9, 19 January 2018

- Java: Handle underscores in versions

## v0.43.8, 18 January 2018

- PHP: Handle pre-release version with a '-' properly

## v0.43.7, 17 January 2018

- JS: Raise evaluatability error when parsing, not resolvability error

## v0.43.6, 17 January 2018

- JS: Raise resolvability error if using workspaces but not private

## v0.43.5, 17 January 2018

- Elixir: Handle `or` requirements betters (by adding another `or` at the end)

## v0.43.4, 17 January 2018

- Elixir: Handle dependency names which are substrings of other dependencies
  names

## v0.43.3, 17 January 2018

- Elixir: Don't do language version checks

## v0.43.2, 17 January 2018

- Java: More robust POM parsing in File Updater

## v0.43.1, 16 January 2018

- Elixir: Install hex before FileParser, if required

## v0.43.0, 16 January 2018

- Add support for Elixir

## v0.42.28, 16 January 2018

- JS: Tighter formula for git dependencies

## v0.42.27, 16 January 2018

- JS: Get package declaration string from package-lock.json, not from
  package.json

## v0.42.26, 15 January 2018

- Find changelogs in a `docs` folder

## v0.42.25, 15 January 2018

- JS: Handle duplicate requirements that are identical

## v0.42.24, 15 January 2018

- PHP: Handle bad git references

## v0.42.23, 15 January 2018

- JS: Explicitly ignore flat resolution dependency files

## v0.42.22, 15 January 2018

- JS: Handle host shortnames in package.json

## v0.42.21, 15 January 2018

- JS: Filter out dependencies with a URL version at parse time

## v0.42.20, 14 January 2018

- JS: Handle multiple declarations for the same dependency

## v0.42.19, 14 January 2018

- JS: Handle dist tags in requirements updater

## v0.42.18, 14 January 2018

- JS: Update git URL dependencies

## v0.42.17, 14 January 2018

- JS: Strip prefixes from JS versions before checking for updated requirements
  in requirement updater

## v0.42.16, 14 January 2018

- JS: Pass requirement update version strings, not hashes

## v0.42.15, 14 January 2018

- JS: Update git dependencies specifed with a GitHub format

## v0.42.14, 11 January 2018

- JS: Handle setups where a lockfile is present by the .npmrc says not to update
  it

## v0.42.13, 11 January 2018

- Collapse paths with a ".." in them when creating PRs

## v0.42.12, 9 January 2018

- Java: Handle versions with capitals in them

## v0.42.11, 9 January 2018

- Docker: Handle private registries without a port

## v0.42.10, 9 January 2018

- Ruby: Don't try to update the Ruby version when updating multiple dependencies

## v0.42.9, 8 January 2018

- Java: Add support for projects that inherit from parent POM (thanks @evenh!)

## v0.42.8, 8 January 2018

- PHP: Check for pre-release versions to update to if using a pre-release
  version

## v0.42.7, 8 January 2018

- JS: Remove imperfect check that yarn.lock was updating

## v0.42.6, 7 January 2018

- Java: Maintain original formatting of pom.xml

## v0.42.5, 6 January 2018

- Java: Use dependency selector from FileParser in FileUpdater

## v0.42.4, 6 January 2018

- Java: Stricter dependency selector in FileParser

## v0.42.3, 5 January 2018

- Handle PR creation when a branch called `dependabot` already exists

## v0.42.2, 5 January 2018

- Sanitize colons out of git branch names

## v0.42.1, 5 January 2018

- Java: Handle dependency declarations without a version requirement

## v0.42.0, 5 January 2018

- Java: Add support for Maven

## v0.41.5, 5 January 2018

- PHP: Use Composer 1.6.0

## v0.41.4, 3 January 2018

- PHP: Handle replaced dependencies

## v0.41.3, 29 December 2017

- JS: Handle versions specified with a dist tag

## v0.41.2, 29 December 2017

- Include git protocol URIs in metadata finder regex
- PHP: Slightly raise Composer memory limit

## v0.41.1, 29 December 2017

- PHP: Use http-basic for GitHub credentials

## v0.41.0, 29 December 2017

- Ruby: Treat minimum possible Ruby requirement as the specified Ruby version,
  when set in gemspec

## v0.40.25, 28 December 2017

- Ruby: Ignore Bundler version if specified in Gemfile

## v0.40.24, 28 December 2017

- Handle removed directories better (by raising a DependencyFileNotFound error)

## v0.40.23, 28 December 2017

- JS: Workaround for Yarn bug that means lockfile doesn't always change

## v0.40.22, 28 December 2017

- JS: Fix false-positive result of wanting pre-release when a .x version was
  requested

## v0.40.21, 27 December 2017

- Python: Look for index URLs in credentials

## v0.40.20, 27 December 2017

- JS: Handle yarn.lock files with multiple entries for the same dependency

## v0.40.19, 26 December 2017

- PHP: Handle wildcard versions better in requirement updater

## v0.40.18, 26 December 2017

- Python: Handle simple index etries with spaces in filenames
- JS: Only request registry index once during update check
- PHP: Handle stability flags in requirements updater

## v0.40.17, 25 December 2017

- JS: Handle pre-release updates when precision needs increasing

## v0.40.16, 25 December 2017

- PHP & JS: Handle pre-releases in a hyphen range

## v0.40.15, 24 December 2017

- Docker: Handle suffices with periods

## v0.40.14, 24 December 2017

- JS: Ensure updates hit specific version

## v0.40.13, 24 December 2017

- Python: Handle setup.py calls to parse_requirements
- JS: Handle Yarn workspaces where the parent package.json is in a directory
- All: Make fewer requests from file fetchers

## v0.40.12, 23 December 2017

- Python: Update regexes to make FileUpdater more accurate

## v0.40.11, 23 December 2017

- Python: Handle local version modifiers in metadata finder

## v0.40.10, 23 December 2017

- Python: Handle local version modifiers

## v0.40.9, 22 December 2017

- Python: Use correct URL for PyPI simple index
- Python: Handle filenames with underscores and periods in updater

## v0.40.8, 22 December 2017

- Python: Handle capitalised dependency names in simple index response

## v0.40.7, 22 December 2017

- Python: Use simple index to find latest version

## v0.40.6, 22 December 2017

- PHP: Don't update composer.json if requirements already met

## v0.40.5, 22 December 2017

- Ruby: Use tag_sha, not commit_sha, when checking if a git dep needs updating

## v0.40.4, 22 December 2017

- JS: Handle pre-release strings properly

## v0.40.3, 22 December 2017

- Raise error in FileUpdaters if lockfile is present and doesn't change

## v0.40.2, 22 December 2017

- JS: Temporarily back out v0.40.0 changes

## v0.40.1, 22 December 2017

- JS: Handle pre-releases in requirement specifiers correctly

## v0.40.0, 21 December 2017

- Don't update package.json and composer.json if requirements already met

## v0.39.26, 21 December 2017

- Python: Actually handle requirements.txt files that self-reference with extras

## v0.39.25, 21 December 2017

- Python: Handle requirements.txt files that self-reference with extras

## v0.39.24, 21 December 2017

- Use semanic prefix for Dependabot PR names (when appropriate)

## v0.39.23, 21 December 2017

- JS: Better handling of global auth credentials in .npmrc

## v0.39.22, 21 December 2017

- Python: Honour existing quote style when updating Pipfile dependencies

## v0.39.21, 21 December 2017

- Python: Handle names that need normalising in Pipfile FileUpdater

## v0.39.20, 21 December 2017

- Python: Handle dependency names with an underscore in Pipfile

## v0.39.19, 21 December 2017

- Python: Handle capitalised dependency names in Pipfile

## v0.39.18, 20 December 2017

- JS: Handle global auth declarations

## v0.39.17, 20 December 2017

- Ruby: Make Ruby library split explicit in UpdateChecker (just a refactor)

## v0.39.16, 19 December 2017

- PHP: Bump composer/composer from 1.5.5 to 1.5.6
- PHP: Show metadata for git dependencies
- JS: Check for dist-tags in npm response
- Docker: Use latest version of docker_registry2

## v0.39.15, 18 December 2017

- Ruby: Clone down submodules when evaluating git dependencies

## v0.39.14, 18 December 2017

- PHP: Stop ignoring git repos

## v0.39.13, 18 December 2017

- PHP: Spec library handling on caret constraints
- PHP: Keep digit length for two-digit caret version

## v0.39.12, 18 December 2017

- PHP: More robust file updating

## v0.39.11, 18 December 2017

- PHP: Update handling of ~ constraints

## v0.39.10, 18 December 2017

- PHP: Handle "v" prefixes in versions

## v0.39.9, 18 December 2017

- JS: Handle versions with a hyphen in them

## v0.39.8, 17 December 2017

- JS: More sophisticated JavaScript requirement updating

## v0.39.7, 17 December 2017

- PHP: Handle hyphen ranges properly
- PHP: Handle range requirements better for app updates

## v0.39.6, 17 December 2017

- PHP: Better requirement updating for library requirements

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
