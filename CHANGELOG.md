## v0.107.22, 26 May 2019

- Elixir: Better file sanitization

## v0.107.21, 26 May 2019

- Gradle: Ignore failure to fetch script plugins from submodules
- Python: Better python version error detection

## v0.107.20, 26 May 2019

- Python: Mark dependencies specified in a _dev file as development dependencies

## v0.107.19, 25 May 2019

- Terraform: Handle unparseable files

## v0.107.18, 25 May 2019

- Gradle: Handle dynamic versions with minimum patch
- Python: Don't parse comments as part of index URL

## v0.107.17, 25 May 2019

- Python: Use configured git when using Poetry
- Ruby: Handle unevaluatable ruby versions

## v0.107.16, 24 May 2019

- JS: Bump tar from 2.2.1 to 2.2.2 in /npm_and_yarn/helpers

## v0.107.15, 24 May 2019

- Python: Handle unreachable git dependencies when using Poetry

## v0.107.14, 24 May 2019

- More retries for PR creation failures

## v0.107.13, 24 May 2019

- Elm: Raise a resolvability error for old versions of Elm
- JS: Bump semver from 6.0.0 to 6.1.0 in /npm_and_yarn/helpers

## v0.107.12, 20 May 2019

- Python: Don't accidentally replace extra declarations with locked versions

## v0.107.11, 20 May 2019

- Maven: Ignore unfetchable parents when finding repositories

## v0.107.10, 20 May 2019

- Raise an identifiable error if GitHub 500s during git metadata lookup

## v0.107.9, 18 May 2019

- Elixir: Cowardly fix for a mixfile updating issue

## v0.107.8, 18 May 2019

- Python: Run check_original_requirements_resolvable using correct Python version

## v0.107.7, 18 May 2019

- Maven: Ignore unfetchable parents
- Python: Bump poetry from 0.12.14 to 0.12.16

## v0.107.6, 16 May 2019

- Make Source#url dependant on hostname

## v0.107.5, 15 May 2019

- Allow custom headers to be passed to pull request creator
- Python: Don't fetch large .txt files

## v0.107.4, 15 May 2019

- Update dependencies label colour

## v0.107.3, 14 May 2019

- Bump dep

## v0.107.2, 13 May 2019

- JS: Ignore quotes in npmrc when looking for registry

## v0.107.1, 13 May 2019

- Python: Handle missing references for Poetry dependencies

## v0.107.0, 12 May 2019

- PHP: Update to minimal secure version for security updates

## v0.106.47, 12 May 2019

- Elixir: Sanitize config_path out of mixfiles

## v0.106.46, 10 May 2019

- Java: Handle branch not found errors in MetadataFinder

## v0.106.45, 10 May 2019

- Bundler: Update lockfiles which have tricky default gem handling

## v0.106.44, 10 May 2019

- JS: Bump @dependabot/yarn-lib from 1.15.2 to 1.16.0 in /npm_and_yarn/helpers
- Python: Bump pip-tools from 3.6.1 to 3.7.0 in /python/helpers

## v0.106.43, 9 May 2019

- Ruby: Better default when replacing file text

## v0.106.42, 9 May 2019

- JS: Handle packages without a name

## v0.106.41, 9 May 2019

- JS: Sanitize spaces in filenames

## v0.106.40, 9 May 2019

- Gradle: Fix VersionFinder for plugins that check maven.google.com

## v0.106.39, 9 May 2019

- Use service pack to determine existing branches

## v0.106.38, 8 May 2019

- Cache that a branch can't be found
- Don't cache a single branch_ref now that branch_exists? takes an argument

## v0.106.37, 8 May 2019

- Bundler: Always include spaces after commas

## v0.106.36, 8 May 2019

- Use updated branch name when creating PRs
- Python: Revert "Ignore irrelevant pyproject files to avoid pep517 warnings"

## v0.106.35, 7 May 2019

- Add longer sleep when creating a commit fails
- Python: Bump pip from 19.1 to 19.1.1 in /python/helpers
- Raise error for unprocessible branch names

## v0.106.34, 6 May 2019

- Python: Downgrade Poetry to avoid bug

## v0.106.33, 5 May 2019

- Bundler: Use --full-index when checking for updates and updating files

## v0.106.32, 3 May 2019

- Docker: Handle v1 dockerhub references

## v0.106.31, 3 May 2019

- Rename github_link_proxy to github_redirection_service
- Python: Don't prioritize Python 2 above lower Python 3 versions
- Python: Bump poetry from 0.12.14 to 0.12.15 in /python/helpers

## v0.106.30, 3 May 2019

- Python: Use python version indicated by markers in compiled pip-compile files
- Allow a custom GitHub link proxy to be provided to MessageBuilder
- Update Rust specs

## v0.106.29, 2 May 2019

- Handle issue linking of issue numbers prefixed with `\#`
- Don't sanitize @-mentions in code quotes

## v0.106.28, 1 May 2019

- Python: Handle sub-dependencies that are removed from the lockfile during update

## v0.106.27, 30 April 2019

- Allow a custom prefix to be passed to BranchNamer

## v0.106.26, 30 April 2019

- Gradle: Parse and update plugin versions

## v0.106.25, 30 April 2019

- Composer: Handle people putting strange things in their repositories hash/array
- Fix error-related rubocops

## v0.106.24, 29 April 2019

- Cargo: Handle private git dependencies that aren't parsed

## v0.106.23, 29 April 2019

- Python: Respect Python version specified in runtime.txt

## v0.106.22, 29 April 2019

- PHP: Fetch path dependencies specified in a hash (rather than an array)

## v0.106.21, 29 April 2019

- Python: Look for .python-version file at top-level, too

## v0.106.20, 28 April 2019

- Rust: Handle a resolvability issue
- Rust: Require a unique source (not just source type)
- Upgrade to PHP 7.3

## v0.106.19, 28 April 2019

- Python: Use Python 3.7.3 instead of 2.6.8
- Python: Bump poetry from 0.12.13 to 0.12.14 in /python/helpers

## v0.106.18, 26 April 2019

- Bump poetry from 0.12.12 to 0.12.13 in /python/helpers

## v0.106.17, 26 April 2019

- Update changelog finder to look in GitLab and Bitbucket directories, too
- Convert GitLab API types to match GitHub

## v0.106.16, 26 April 2019

- Sanitize all tags in commit messages

## v0.106.15, 26 April 2019

- Clean up tag sanitization and details tag creation

## v0.106.14, 26 April 2019

- Escape more tags when sanitizing lines
- Replace empty links (caused by rst processing)
- NPM: Remove extraneous git url fix

## v0.106.13, 26 April 2019

- Docker: Make self.updated_files_regex case insensitive

## v0.106.12, 25 April 2019

- NPM: Preserve indentation of lockfiles

## v0.106.11, 25 April 2019

- Python: Update to a specific version when updating Pipenv subdependencies
- Python: Update poetry sub-dependencies to a specific version
- Require minimum file size for changelogs

## v0.106.10, 25 April 2019

- Add php7.2-mysql providing pdo-mysql

## v0.106.9, 25 April 2019

- Add scope to fallback commit message
- Python: Ignore irrelevant pyproject files to avoid pep517 warnings
- Python: Bump pip from 19.0.3 to 19.1 in /python/helpers
- Python: Bump pip-tools from 3.6.0 to 3.6.1 in /python/helpers (#1120)

## v0.106.8, 24 April 2019

- NPM: Handle private registry error '403 Fobidden'
- JS: Handle git dependenices with file-path sub-dependencies

## v0.106.7, 24 April 2019

- Rust: Update target-specific dependencies

## v0.106.6, 24 April 2019

- Rust: Handle git dependencies changing version to a pre

## v0.106.5, 23 April 2019

- JS: Add floor to satisfying_versions in version resolver

## v0.106.4, 23 April 2019

- JS: Ignore aliased dependencies in lockfile parser

## v0.106.3, 23 April 2019

- Rust: Require a resolvable version, even when updating a library

## v0.106.2, 23 April 2019

- Ruby: Include a lower Ruby version in list of possible rubies (in case a < req specified)
- Add sleep before retrying commit creation

## v0.106.1, 22 April 2019

- Make commit prefixing more robust

## v0.106.0, 21 April 2019

- Pass old commit SHA when updating a PR, and use it to identify the relevant commit
- Composer: Add lowest_security_fix_version to LatestVersionFinder
- Composer: Refactor LatestVersionFinder to be more extensible
- Composer: Move tests for latest version finding to new class
- Composer: Extract latest_version logic into LatestVersionFinder class
- Composer: Stop passing latest_version to RequirementsUpdater (it was unused)
- Rust: Update to lowest fixed version for vulnerable dependencies
- Rust: Pass a single version to RequirementsUpdater

## v0.105.8, 19 April 2019

- Python: Handle subdependency resolution checking properly for pip-compile

## v0.105.7, 18 April 2019

- Stop using commit compare API endpoint when building commit diffs (it sometimes 500s)

## v0.105.6, 18 April 2019

- Python: Add `resolvable?` method to version resolvers, and use in update checkers

## v0.105.5, 18 April 2019

- JS: Handle cases where requirements stay identical except for switch to private source

## v0.105.4, 18 April 2019

- Ruby: Handle Ruby lock errors correctly in LockfileUpdater
- Ruby: Update versions constant

## v0.105.3, 18 April 2019

- Python: Handle lockfile-only updates with an unrelated requirement
- Rust: Tell rustup to use cURL
- Rust: Change ownership of /opt/rust in dev dockerfile

## v0.105.2, 18 April 2019

- Rust: Add LatestVersionFinder#lowest_security_fix_version
- Rust: Extract specs for LatestVersionFinder
- Rust: Extract latest version finder logic into separate class

## v0.105.1, 17 April 2019

- JS: Handle MyGet format resolved URLs

## v0.105.0, 17 April 2019

- Python: Update to lowest fix for security vulnerabilities (all package managers)

## v0.104.6, 17 April 2019

- Python: Refactor PipCompileVersionResolver to match other resolvers
- Python: Refactor PoetryVersionResolver to match PipenvVersionResolver
- Python: Refactor PipenvVersionResolver#latest_resolvable_version to take a
  requirement arg
- Python: Refactor PipenvVersionResolver to make it more extensible
- PHP: Re-remove Xdebug

## v0.104.5, 17 April 2019

- Add back x-debug

## v0.104.4, 17 April 2019

- JS: Handle package.json files that specify an array of dependencies (not an object)

## v0.104.3, 17 April 2019

- Remove xdebug from container
- Rename pipfile resolver to pipenv

## v0.104.2, 17 April 2019

- Python: Refactor UpdateChecker to make it more extensible
- Python: Rename PipfileVersionResolver to PipenvVersionResolver
- Python: Update to lowest fixed version for vulnerable requirement.txt versions
- Python: Add lowest_security_fix_version to UpdateChecker::LatestVersionFinder
- Python: Pass security_advisories to LatestVersionFinder

## v0.104.1, 17 April 2019

- Add mercurial to Dockerfile
- Ruby: Minor efficiency improvement in LatestVersionFinder
- Python: Refactor LatestVersionFinder to make private methods easier to reuse
- Add tests for Python::UpdateChecker::IndexFinder
- Python: Split index finder logic into separate class
- More simplification of Bundler::UpdateChecker
- Clean up Bundler::UpdateChecker::LatestVersionFinder

## v0.104.0, 16 April 2019

- Ruby: Update to minimal version possible for security updates

## v0.103.3, 14 April 2019

- Python: Fix handling of comparisons with non-canonical segments

## v0.103.2, 14 April 2019

- Python: Support pre-releases in wildcards, and allow Python 3.8-dev

## v0.103.1, 14 April 2019

- Composer: Build path dependencies from lockfile even when whole dir is missing

## v0.103.0, 14 April 2019

- Require a dependency_name when creating a SecurityAdvisory
- Python: Bump cython from 0.29.6 to 0.29.7

## v0.102.1, 12 April 2019

- JS: Don't assume we can upgrade sub-dependencies to a secure verison

## v0.102.0, 12 April 2019

- JS: Update insecure dependencies to the minimum secure version

## v0.101.2, 12 April 2019

- Nuget: support lowercase version attributes
- JS: Pass security advisories to LatestVersionChecker

## v0.101.1, 12 April 2019

- JS: Fix update checker for deprecated deps

## v0.101.0, 12 April 2019

- Gradle: Upgrade to lowest fixed version if a dependency is vulnerable
- .NET: Upgrade to lowest fixed version if a dependency is vulnerable
- Maven: Upgrade to lowest fixed version if a dependency is vulnerable
- Maven: Cache release checks

## v0.100.2, 12 April 2019

- Ignore closed PR errors when updating a PR's branch

## v0.100.1, 12 April 2019

- Don't re-cast versions to versions in SecurityAdvisory

## v0.100.0, 12 April 2019

- Bump poetry from 0.12.11 to 0.12.12 in /python/helpers
- Add SecurityAdvisory class, used in UpdateCheckers::Base to determine if a
  version is vulnerable
- NPM: Remove dry-run config setting
- Add UpdateCheckers::Base#vulnerable? method, which checks against security advisories
- Accept a security_advisories argument to UpdateCheckers::Base.new

## v0.99.7, 10 April 2019

- JS: Handle build metadata in version strings

## v0.99.6, 10 April 2019

- Gradle: Handle commented out lines when updating files
- Python: Handle wildcards in requirements with a non-equality operator

## v0.99.5, 10 April 2019

- .NET: Treat dependency names as case-insensitive

## v0.99.4, 10 April 2019

- PHP: Bump composer/composer from 1.8.4 to 1.8.5

## v0.99.3, 9 April 2019

- Handle deleted target branches when creating a PR
- Python: Use pyenv v1.2.11 in Dockerfile, and update available Python versions

## v0.99.2, 9 April 2019

- Nuget: support multiple .sln files

## v0.99.1, 8 April 2019

- Git submodules: Raise parser error for trailing slashes in path

## v0.99.0, 5 April 2019

- NPM: Fix "premature close" for git dependencies

## v0.98.78, 5 April 2019

- Gradle: Better PROPERTY_REGEX

## v0.98.77, 5 April 2019

- Python: Raise error for invalid poetry requirements
- Ruby: Ignore Bundler updates if requirement is non-trivial
- Python: Bump pip-tools from 3.5.0 to 3.6.0 in /python/helpers

## v0.98.76, 4 April 2019

- NPM: Fix git dependencies with invalid requires

## v0.98.75, 4 April 2019

- JS: Handle invalid requirements better, and ignore rogue equal signs
- Docker: Treat RestClient::Exceptions::ReadTimeout exceptions the same as RestClient::Exceptions::OpenTimeout

## v0.98.74, 4 April 2019

- Better GitHub link replacement
- Maven: Handle requirements which include underscores

## v0.98.73, 4 April 2019

- Ruby: Don't ignore all > requirements in ForceUpdater
- Ruby: Only consider relevant conflicts when unlocking additional deps

## v0.98.72, 3 April 2019

- Maven: Include http:// version of central registry in special handling

## v0.98.71, 2 April 2019

- Docker: make ECR requests work w/o credentials

## v0.98.70, 2 April 2019

- Ruby: Always evaluate files from within a base directory

## v0.98.69, 2 April 2019

- Cargo: Handle additional error type that represents an unreachable git repo

## v0.98.68, 2 April 2019

- Yarn: ignore platform check

## v0.98.67, 2 April 2019

- PHP: Move back to clearer memory limit setting

## v0.98.66, 2 April 2019

- NPM: ignore prepare and prepack scripts when installing git dependencies

## v0.98.65, 2 April 2019

- Add fallback PHP environment variable

## v0.98.64, 2 April 2019

- Docker: Handle invalid file encoding

## v0.98.63, 1 April 2019

- Add an automerge label to automerge candidates if one is present

## v0.98.62, 1 April 2019

- JS: Look for dependency details in a lockfile that might match this manifest (not any lockfile)

## v0.98.61, 1 April 2019

- Revert "Bundler: Include protocol when raising PrivateSourceAuthenticationFailure errors"

## v0.98.60, 1 April 2019

- Bump semver from 5.6.0 to 6.0.0 in /npm_and_yarn/helpers

## v0.98.59, 1 April 2019

- Maven: Better dot separator regex in PropertyValueFinder

## v0.98.58, 1 April 2019

- JS: Don't mistake v-prefixed versions for distribution tags

## v0.98.57, 1 April 2019

- Python: Case insensitive check for whether dependency name is in error message

## v0.98.56, 1 April 2019

- JS: Ignore 500s from private registries
- .NET: Handle property versions that reference a function

## v0.98.55, 31 March 2019

- JS: Handle npm lockfile name substitution in post-processing

## v0.98.54, 31 March 2019

- JS: Don't replace package name when generating updated npm lockfile

## v0.98.53, 30 March 2019

- Python: Handle environment variables for Gemfury URLs

## v0.98.52, 29 March 2019

- Pass empty string token to elixir helper, again

## v0.98.51, 30 March 2019

- Ruby: Include protocol when raising PrivateSourceAuthenticationFailure errors
- Elixir: Pass empty string token to elixir helper
- JS: Better regsitry uniq-ing

## v0.98.50, 29 March 2019

- Bundler: Handle resolver returning `nil` for an unchanged git source

## v0.98.49, 28 March 2019

- Handle missing token in js registry finder

## v0.98.48, 29 March 2019

- Don't attempt to configure git creds that don't have a username or password

## v0.98.47, 28 March 2019

- Python: Handle basic auth credentials that include an `@` in the username

## v0.98.46, 28 March 2019

- NPM: Optionally build npmrc without credentials

## v0.98.45, 28 March 2019

- Bundler: Handle repos without a lockfile where the dep being updated has an implicit pre-release requirement

## v0.98.44, 27 March 2019

- Python: Fetch requirement files with lines that start with a comment

## v0.98.43, 27 March 2019

## v0.98.42, 27 March 2019

- Bump @dependabot/yarn-lib from 1.13.0 to 1.15.2 in /npm_and_yarn/helpers

## v0.98.41, 26 March 2019

- Python: Handle yanked dependencies in PoetryVersionResolver
- Python: Better environment variable support in LatestVersionFinder
- Fix rubocop

## v0.98.40, 26 March 2019

- Python: Handle environment variables in LatestVersionFinder

## v0.98.39, 26 March 2019

- Python: Fix copy-paste error

## v0.98.38, 26 March 2019

- Bundler: Handle tricky ruby requirements in a gemspec when generating new lockfiles

## v0.98.37, 26 March 2019

- Python: Handle errors due to updating a dep to a version with a Python requirement issue (poetry)
- Add handling for tree creation race to pull request updater

## v0.98.36, 26 March 2019

- Handle unexpected previous versions in CommitsFinder

## v0.98.35, 25 March 2019

- Bundler: Don't add .rb suffix to require_relative files that already include it

## v0.98.34, 25 March 2019

- Python: Don't include dependencies parsed from a req.txt that are also included in Poetry
- Maven: Better file update regex (trust declaration finder more)
- JS: try/catch helper scripts

## v0.98.33, 25 March 2019

- Yarn: install specific sub-dependency version

## v0.98.32, 25 March 2019

- Composer: Serve resolvability error if required connections are disallowed
- Allow config variables without credentials wherever possible

## v0.98.31, 22 March 2019

- Python: Allow credentials to be passed with a token
- Use Bitbucket client in GitCommitChecker
- Use GitLab client when doing commit comparison

## v0.98.30, 22 March 2019

- Python: Reorganize FileUpdater#resolver_type to better handle cases where req.txt needs updating
- Python: More marker parsing improvements
- Python: Better handling of markers in requirements.txt

## v0.98.29, 22 March 2019

- Composer: Correct name for path deps starting with ../
- Yarn: handle git dependencies with token

## v0.98.28, 22 March 2019

- .NET: More sophisticated property value updater

## v0.98.27, 21 March 2019

- Maven: Handle repeated dependency declarations with different scopes

## v0.98.26, 21 March 2019

- Python: Handle updating Pipfiles which declare a version in a table

## v0.98.25, 21 March 2019

- Python: Split Pipfile manifest updater into separate class
- Use GitHub repo name defintion for GitLab and Azure
- PHP: Handle relative paths that are actually from the root
- Rebuild Dockerfile using Ruby 2.6.2

## v0.98.24, 21 March 2019

- Ruby: Update list of latest rubies
- Python: Narmalise dependency names when looking for them in poetry lockfile
- Do two retries when attempting to fetch git metadata
- Maven: Handle case where declaration_pom_name isn't found

## v0.98.23, 21 March 2019

- Python: Handle v-prefixes in versions and requirements

## v0.98.22, 21 March 2019

- PHP: Update memory limit setting again

## v0.98.21, 20 March 2019

- Python: refactor escaped command string
- Dep: escape command
- Cargo: escape command
- Fix escaped command for composer
- Escape shared helpers run subprocess cmd by default

## v0.98.20, 20 March 2019

- Python: Use original manifest instead of original compiled file when unredacting creds if required

## v0.98.19, 20 March 2019

- Python: Handle git credentials getting redacted as part of pip-compile install process
- Go: Retry transitory Go resolution issues
- Python: Remove unnecessary install

## v0.98.18, 20 March 2019

- Rust: Fetch patched path dependencies

## v0.98.17, 19 March 2019

- Use updated (clearer) style in other PHP helper

## v0.98.16, 19 March 2019

- Use Dependabot::Clients::GitlabWithRetries.for_source in labeler
- Python: Use 2.7.16
- Python: Use latest pyenv commit to get Python 2.7.16

## v0.98.15, 19 March 2019

- Python: Raise a DependencyFileNotResolvable error for unsupported pip-compile constraints

## v0.98.14, 19 March 2019

- Python: Use build isolation in FileUpdater
- Assume closing index of 0 if one can't be found
- Add test to ensure build-isolation not required in Python file updater

## v0.98.13, 19 March 2019

- Python: Build in isolation when using pip-tools (to prevent errors when using a pyproject.toml)

## v0.98.12, 19 March 2019

- Use php7.2-zmq instead of php-zmq

## v0.98.11, 19 March 2019

- .NET: Only update pre-release versions to pre-s for the same version
- Docker: Tighter regex for updating version

## v0.98.10, 18 March 2019

- Python: Don't escape spaces in pip-compile options

## v0.98.9, 18 March 2019

- Gradle: Handle multiple updates to a superstring
- .NET: Raise parser error for unparseable JSON

## v0.98.8, 18 March 2019

- Python: escape child process commands

## v0.98.7, 18 March 2019

- Stricter regex for Python file correctness

## v0.98.6, 18 March 2019

- Python: Better regex for dependency names
- Remove redundant require

## v0.98.5, 17 March 2019

- PHP: Remove overzealous use of shellwords

## v0.98.4, 16 March 2019

- Gradle: Handle property declarations in namespaces
- Gradle: Minor cleanup (uniq files)

## v0.98.3, 16 March 2019

- .NET: Update NuGet packages in global.json

## v0.98.2, 15 March 2019

- Docker: Raise custom error when private registries time out fetching tags

## v0.98.1, 15 March 2019

- Sign commits on behalf of an org
- Add support_file to DependencyFile#to_h

## v0.98.0, 15 March 2019

- Python: Avoid shelling out to Python during file fetching
- JS: Don't shell out to JavaScript during file fetching
- Ruby: Remove all calls to eval from file fetching

## v0.97.11, 15 March 2019

- JS: Fix native helper path in development and test

## v0.97.10, 14 March 2019

- Cargo: Remove lockfile duplicates

## v0.97.9, 14 March 2019

- Revert changes to JS helpers in dev and test env

## v0.97.8, 14 March 2019

- Handle 409s from GitHub when constructing commit message
- JS: Use un-built helpers in development and test env

## v0.97.7, 13 March 2019

- Short circuit update checking for dependencies being ignored

## v0.97.6, 13 March 2019

- NPM: Raise helpful error when lockfile is corrupt
- Bump pip-tools from 3.4.0 to 3.5.0 in /python/helpers
- Bump jest from 24.4.0 to 24.5.0 in /npm_and_yarn/helpers

## v0.97.5, 11 March 2019

- Elm: clean up subprocess invocation

## v0.97.4, 11 March 2019

- Dep: clean up subprocess invocation
- Composer: clean up subprocess invocation
- Cargo: clean up subprocess invocation
- Go (modules): clean up subprocess invocations

## v0.97.3, 10 March 2019

- Prefer non-app github.com token in SharedHelpers.configure_git_credentials
- Handle invalid milestones quietly

## v0.97.2, 7 March 2019

- Ignore 404s when attempting to set assignees
- JS: Bump npm from 6.8.0 to 6.9.0 in /npm_and_yarn/helpers

## v0.97.1, 5 March 2019

- Handle tags that match our version regex but don't have valid versions
- Bundler: Handle marshall errors

## v0.97.0, 5 March 2019

- Composer: Install php7.2-gmp
- Bundler: Bump rubygems from 3.0.2 to 3.0.3
- JS: Bump eslint from 5.14.1 to 5.15.1 in /npm_and_yarn/helpers

## v0.96.1, 4 March 2019

- Go (modules): handle another case of module path mismatches

## v0.96.0, 4 March 2019

- Minor version bump to signify that JS refactor (included in v0.95.85) is a
  breaking change, as it requires an update to the Dockerfile as well as the
  gem

## v0.95.85, 4 March 2019

- Fix gitignore for npm and yarn helpers
- JS: Ignore URL-style versions in npm lockfiles in NpmAndYarn::FileParser::LockfileParser
- Ruby: Handle marshal dump errors more gracefully
- Composer: Automatically retry transitory errors in VersionResolver
- Add php-zmq to Dockerfile
- JS: Simplify helper usage to only one script (#988)

## v0.95.84, 2 March 2019

- Better tag comparison in CommitsFinders
- Ruby: Handle circular dependencies at the latest version
- Terraform: Parse `git@github.com:` module sources

## v0.95.83, 28 February 2019

- JS: Fetch numeric version for git dependencies with a semver requirement
- Python: Handle .zip or .whl suffices in LatestVersionFinder
- Python: Bump cython from 0.29.5 to 0.29.6 in /python/helpers

## v0.95.82, 28 February 2019

- Prefer refs to versions when generating compare URLs for git updates

## v0.95.81, 27 February 2019

- Python: Raise a resolvability error for Python version conflicts when Python version is user-defined
- Go (modules): switch back to mastermind/vsc now 1.13 is out

## v0.95.80, 27 February 2019

- Ruby: Fix gemspec sanitizer, and update test to have a Gem::Version

## v0.95.79, 27 February 2019

- Ruby: Alternative approach to sanitizing version constants in gemspecs
- Ruby: Only sanitize versions when they appear in strings

## v0.95.78, 27 February 2019

- JS: Treat projects with invalid names as non-library

## v0.95.77, 27 February 2019

- Python: handle fetching whl files dependencies

## v0.95.76, 27 February 2019

- Ruby: Handle more gemspec sanitization

## v0.95.75, 27 February 2019

- Ruby: More gemspec sanitization
- PHP: Build path dependencies from lockfile if not fetchable

## v0.95.74, 26 February 2019

- Go (modules): prevent all pseudo version updates
- Dockerfile: Add bzr to the Dockerfile

## v0.95.73, 26 February 2019

- NPM: Fix lockfile for git deps with semver version

## v0.95.72, 26 February 2019

- Handle TomlRB::ValueOverwriteError everywhere we handle TomlRB::ParseError

## v0.95.71, 26 February 2019

- Rust: Handle TomlRB::ValueOverwriteError errors in FileParser
- Rust: Handle parse errors in unprepared files in VersionResolver

## v0.95.70, 26 February 2019

- Retry GitLab 502s everywhere

## v0.95.69, 25 February 2019

- Ruby: Handle pre-releases with numeric parts in the pre-release specifier

## v0.95.68, 25 February 2019

- Fix handling of docker dependencies in ChangelogFinder

## v0.95.67, 25 February 2019

- Maven: Treat dependencies that specify their scope as `test` as development dependencies

## v0.95.66, 25 February 2019

## v0.95.65, 25 February 2019

- JS: Fix peer dependency updates for libraries

## v0.95.64, 25 February 2019

- JS: Return a version instance from UpdateChecker#latest_resolvable_version_with_no_unlock when version is numberic

## v0.95.63, 25 February 2019

- JS: Handle non-JSON responses from private registries when checking git deps
- JS: Handle duplicate peer dependency error

## v0.95.62, 25 February 2019

- Fix changelog fetching with a suggested changelog URL and no source
- PHP: Automatically retry transitory errors in lockfile updater
- Ruby: Better requirement string parsing

## v0.95.61, 23 February 2019

- Python: Fix python version installed check
- Use Ruby 2.6.1

## v0.95.60, 23 February 2019

- Python: Be explicit about the python version being installed

## v0.95.59, 23 February 2019

- Python: Better Python version handling for Pipenv
- Python: List supported versions, and error if using an unsupported one
- Bump pyenv, Go and Elixir versions in Dockerfile

## v0.95.58, 22 February 2019

- Go (modules): tighten up error regex

## v0.95.57, 22 February 2019

- Go (modules): Handle module path mismatch errors

## v0.95.56, 22 February 2019

- NPM: Fix missed lerna peer dependency update
- Reduce robocop config spread and cover root files

## v0.95.55, 22 February 2019

- Python: Use user's defined Python version when compiling pip-compile files
- Retry GitHub races when creating a commit from a new tree

## v0.95.54, 21 February 2019

- Python: Treat install_requires dependencies as production dependencies
- Ruby: Don't mistake support files for evaled gemfiles

## v0.95.53, 21 February 2019

- Go (modules): handle missing sub-dependency error

## v0.95.52, 21 February 2019

- Ruby: Implement suggested_changelog_url, based on changelog_uri in gemspec
- Add suggested_changelog_url method to MetadataFinder::Base, that is passed to
  ChangelogFinder
- Python: Bump pip from 19.0.2 to 19.0.3 in /python/helpers

## v0.95.51, 20 February 2019

- NPM: Sanitise extra trailing slash from private registries
- Python: Don't repeatedly parse Pipfile.lock

## v0.95.50, 20 February 2019

- Python: Fetch poetry path dependencies
- Python: Only parse large lockfiles once

## v0.95.49, 20 February 2019

- Ruby: Handle another gem not found error case

## v0.95.48, 20 February 2019

- JS: Actually special case DefinitelyTyped

## v0.95.47, 20 February 2019

- JS: Don't update source from git to registry just because version isn't a SHA
- JS: Include a leading `*` as a semver indicator
- Python: Bump pip-tools from 3.3.2 to 3.4.0 in /python/helpers
- Ruby: Allow gemspec dependencies to have a source (in case it's git)

## v0.95.46, 19 February 2019

- Cargo: fix git credential helper issue

## v0.95.45, 19 February 2019

- .NET, Ruby and Rust: Fix directory handling for deeply nested file fetching

## v0.95.44, 19 February 2019

- Reverse commits when building a monorepo compare URL

## v0.95.43, 19 February 2019

- JS: Better special casing for gatsby
- Python: Look in project_urls for homepage
- PHP: Use the global variable $memory when freeing it

## v0.95.42, 19 February 2019

- Rust: Handle non-existent packages

## v0.95.41, 19 February 2019

- Simpler tag sorting for finding most appropriately named tag

## v0.95.40, 19 February 2019

- Better commit fetching for monorepos
- Always prefer commits URL with path for monorepos

## v0.95.39, 19 February 2019

- NPM: Fix lockfile for git dependencies using tags

## v0.95.38, 19 February 2019

- Better lowest_tag_satisfying_previous_requirements lookup

## v0.95.37, 18 February 2019

- Fetch git tags from git upload pack, rather than APIs, in CommitsFinder
- Speed up GitCommitChecker tag processor

## v0.95.36, 18 February 2019

- JS: Add special cases for Gatsby and DefinitelyTyped repos

## v0.95.35, 18 February 2019

- NPM: Speed up sub-dependency updates for big lerna projects using npm
- Composer: Bump friendsofphp/php-cs-fixer from 2.14.1 to 2.14.2 in /composer/helpers

## v0.95.34, 17 February 2019

- JS: Include details of directory in source if included in repository object
- Append directory to source URL when reliable
- Include directory details in commits URL if reliable
- Make source attributes editable, and add Source#url_with_directory method

## v0.95.33, 16 February 2019

- JS: Only assign a single credential to a scope in npmrc builder

## v0.95.32, 15 February 2019

- Ruby: Update version requirement at the same time as updating git tag

## v0.95.31, 15 February 2019

- JS: Parse full nexus private repository URLs from lockfile entries for scoped dependencies

## v0.95.30, 15 February 2019

- JS: Better handling of incorrect credentials for a private registry
- Better commit comparison links for dependencies without a previous version

## v0.95.29, 15 February 2019

- Fetch files from symlinked directories if fetching submodules

## v0.95.28, 14 February 2019

- Go (modules): more detailed error messages for unresolvable dependencies due
  to git errors, and for go.sum checksum mismatches.

## v0.95.27, 14 February 2019

- NPM: Prefer offline cache and turn off audits

## v0.95.26, 14 February 2019

- Go (modules): detect and handle missing/invalid dependency specified with
  pseudo version

## v0.95.25, 14 February 2019

- Cargo: Include all unreachable git dependencies when raising GitDependenciesNotReachable
- Fix time taken measurement for shell cmds
- Add git_repo_reachable? method to GitCommitChecker

## v0.95.24, 14 February 2019

- Cargo: Handle unreachable git dependencies

## v0.95.23, 14 February 2019

- Another @-mention sanitization improvement (better regex)
- JS: Bump npm from 6.7.0 to 6.8.0 in /npm_and_yarn/helpers

## v0.95.22, 14 February 2019

- Cleaner mention sanitizing (use a zero width character)

## v0.95.21, 14 February 2019

- Better sanitization of @mentions when wrapped in a link

## v0.95.20, 13 February 2019

- Update issue tag regex

## v0.95.19, 13 February 2019

- Add optional dependency on Pandoc that allows us to convert rst files

## v0.95.18, 13 February 2019

- PHP: Handle integer versions in composer.lock
- Add .gitignore
- Base: Convert directory to proper path before using it in file fetchers

## v0.95.17, 12 February 2019

- Python: Dig into source URL looking for reference to dependency name
- Gradle: Handle $rootDir variable in dependency script plugins

## v0.95.16, 12 February 2019

- Common: include bin files in dependabot-common packaged gem
- Require common in dry run script

## v0.95.15, 12 February 2019

- Sanitize @-mentions that are prefixed with a dash

## v0.95.14, 12 February 2019

- Python: Don't try to update 'empty' requirements.txt files as part of a Pipfile update
- PHP: Bump composer/composer from 1.8.3 to 1.8.4 in /composer/helpers
- Python: Check source project_url for a GitHub link in MetadataFinder

## v0.95.13, 11 February 2019

- Better branch naming when updating multiple deps

## v0.95.12, 11 February 2019

- JS: Handle registries that don't escape slashes in dependency names except at /latest

## v0.95.11, 11 February 2019

- Gradle: Fetch plugin script files, and update them
- PHP: Handle another error

## v0.95.10, 11 February 2019

- Python: Bump pip from 19.0.1 to 19.0.2 in /python/helpers
- Python: Bump cython from 0.29.4 to 0.29.5 in /python/helpers

## v0.95.9, 10 February 2019

- Rust: Fix method name typo

## v0.95.8, 10 February 2019

- Rust: Fix over-eager manifest file updating
- JS: Better handling of multiple git requirements

## v0.95.7, 8 February 2019

- Bundler: fix gemspec since 1ddf668

## v0.95.6, 8 February 2019

- Go (modules): handle vanity urls that return non-200 responses
- Bundler: remove unnecessary helpers

## v0.95.5, 8 February 2019

- Paginate through GitLab labels
- Python: Make post version comparison logic more explicit

## v0.95.4, 8 February 2019

- Python: Fix bug in post release version comparison

## v0.95.3, 8 February 2019

- Ruby: Handle assignment to hash attributes in sanitizer

## v0.95.2, 7 February 2019

- Fix common gemspec

## v0.95.1, 7 February 2019

- Python: Handle post-release versions properly

## v0.95.0, 7 February 2019

- PHP: Handle version requirements with a trailing dot
- Move shared code to a new `dependabot-common` gem
- Bump gitlab from 4.8 to 4.9
- Align GitLab PR creator with generic options

## v0.94.13, 7 February 2019

- Handle target branches that are a substring

## v0.94.12, 6 February 2019

- Python: Fetch vendored .zip files

## v0.94.11, 6 February 2019

- Correct relative links from GitHub release notes

## v0.94.10, 5 February 2019

- Cargo: Better spec construction

## v0.94.9, 5 February 2019

- Docker: Handle tags with both a prefix and a suffix

## v0.94.8, 4 February 2019

- Cargo: More specific details of dependency being updated

## v0.94.7, 3 February 2019

- Add php-mongodb to Dockerfile

## v0.94.6, 3 February 2019

- Raise normal error when submodule source isn't supported

## v0.94.5, 3 February 2019

- JS: Look for login form redirects, not 404s, when checking packages on npmjs.com

## v0.94.4, 3 February 2019

- Fetch files that are nested in submodules if asked
- Clean up file fetcher base class

## v0.94.3, 2 February 2019

- Better name for language label details

## v0.94.2, 2 February 2019

- Add class attribute_reader to Labler
- Ruby: Move bundler monkey patches
- Python: Bump cython from 0.29.3 to 0.29.4 in /python/helpers

## v0.94.1, 1 February 2019

- Add bundler to omnibus

## v0.94.0, 1 February 2019

- Reorg bundler

## v0.93.17, 1 February 2019

- JS: Better detection of whether an npm registry needs auth
- Increase max retries for GitHub client
- Python: Bump hashin from 0.14.4 to 0.14.5 in /python/helpers

## v0.93.16, 31 January 2019

- Go: Retry resolvability errors in parser

## v0.93.15, 31 January 2019

- Python: Handle Poetry solver problems

## v0.93.14, 31 January 2019

- Add workaround for GitHub bug during PR creation
- PHP: Bump composer/composer from 1.8.2 to 1.8.3 in /composer/helpers
- Python: Bump hashin from 0.14.2 to 0.14.4 in /python/helpers

## v0.93.13, 30 January 2019

- .NET: Handle Nuget sources that don't return a ProjectUrl

## v0.93.12, 30 January 2019

- JS: Return a NpmAndYarn::Version, not a string, for git semver dependencies
- PHP: Bump composer/composer from 1.8.0 to 1.8.2 in /composer/helpers

## v0.93.11, 29 January 2019

- Gradle: Handle tabs when looking for repositories

## v0.93.10, 29 January 2019

- JS: Parse the semver version, rather than the git SHA, for git reqs with a semver specification

## v0.93.9, 29 January 2019

- Python: Handle Apache Airflow 1.10.x installs with pip-compile

## v0.93.8, 29 January 2019

- Maven: Update dot separator regex

## v0.93.7, 28 January 2019

- Python: Fix sanitization and remove puts calls

## v0.93.6, 28 January 2019

- Python: Sanitize # symbols in pyproject.toml files
- Python: Bump pip-tools from 3.3.1 to 3.3.2 in /python/helpers

## v0.93.5, 27 January 2019

- Maven: Handle case where property value can't be found in MetadataFinder

## v0.93.4, 27 January 2019

- Maven: Substitute properties in the URL when fetching a parent POM file

## v0.93.3, 27 January 2019

- Python: Handle fetching gzipped path dependencies

## v0.93.2, 26 January 2019

- Python: Handle Poetry sub-deps that should be removed from the lockfile
- JS: Fix bug when updating npm@5 lockfile w/ npm@6.6.0

## v0.93.1, 25 January 2019

- Merge branch 'fix-js-helper-location'
- Log when CIRCLE_COMPARE_URL isn't set
- Rubocop
- Fix JS helper location
- Merge branch 'hex-build-script-fix'
- Fix hex build script
- Revert "Revert "Make hex helpers obey install_dir""

## v0.93.0, 25 January 2019

- Python: Bump pip from 18.1 to 19.0.1 in /python/helpers
- Python: Bump pip-tools from 3.1.0 to 3.3.1 in /python/helpers

## v0.92.8, 24 January 2019

- Python: Fix for post-processing compiled files with reordered indices
- JS: Bump npm from 6.6.0 to 6.7.0 in /npm_and_yarn/helpers

## v0.92.7, 24 January 2019

- Make python helpers obey install_dir
- Make npm_and_yarn build script obey install_dir

## v0.92.6, 23 January 2019

- Python: Use poetry update [dep-name] --lock when updating Poetry files

## v0.92.5, 22 January 2019

- Ruby: CGI escape credentials before passing to Bundler
- PHP: Clean Composer programmatically install

## v0.92.4, 22 January 2019

- Rust: Raise PathDependenciesNotReachable errors, rather than
  DependencyFileNotFound errors

## v0.92.3, 22 January 2019

- JS (npm): Fix invalid from for git sub-dependencies
- Reduce "running as root" warnings with Docker image

## v0.92.2, 21 January 2019

- Update .gitignore

## v0.92.1, 21 January 2019

- Update gitignore for npm_and_yarn helpers move

## v0.92.0, 21 January 2019

- .NET, Elixir and Pythnon: Better handling of version with build/local part
- JS: Simplify npm_and_yarn helpers to yarn workspaces
- JS: Bump npm from 6.5.0 to 6.6.0 in /npm_and_yarn/helpers/npm
- JS: Handle sub-dep version resolution errors
- Python: Bump cython from 0.29.2 to 0.29.3 in /python/helpers
- Python: Bump hashin from 0.14.1 to 0.14.2 in /python/helpers

## v0.91.8, 20 January 2019

- JS: Add support for Yarn git semver
- PHP: Always pass to json_encode for secure output
- PHP: Switch to a real helper bin file

## v0.91.7, 20 January 2019

- .NET: Handle build versions

## v0.91.6, 20 January 2019

- Add php7.2-apcu to Dockerfile

## v0.91.5, 18 January 2019

- Python: Fetch cascading requirement.in files
- Better commit subject truncation

## v0.91.4, 17 January 2019

- Docker: Handle AWS auth errors

## v0.91.3, 17 January 2019

- Raise NoHistoryInCommon error if it blocks PR creation

## v0.91.2, 17 January 2019

- JS: Stop registering the wrong version class

## v0.91.1, 17 January 2019

- JS: Memoize lockfile updates
- JS: Only include relevant dependency files when updating files

## v0.91.0, 17 January 2019

- JS: Reorganise into npm_and_yarn directory
- Elixir: require fully released version of jason
- Remove possibly redundant check that npm lockfile has changed
- JS: Add error context when no files where updated
- Update license to 2.0
- Fix README typo
- Dep: Ignore indirect dependencies in latest_resolvable_version_with_no_unlock

## v0.90.7, 15 January 2019

- Dep: Ignore indirect dependencies more robustly
- .NET: Even longer timeout

## v0.90.6, 14 January 2019

- Handle git to registry PRs for libraries in PR message builder

## v0.90.5, 14 January 2019

- Fix typo

## v0.90.4, 14 January 2019

- Rust: Handle old version of resolution failure error (for when toolchain specified)
- Use Elixir 1.8.0

## v0.90.3, 14 January 2019

- PHP: Handle registries that 404 on /packages.json

## v0.90.2, 14 January 2019

- Docker: Simplify updated_digest fetching, and retry DockerRegistry2::NotFound on tags
- Rust: Handle no latest_version when updating a library

## v0.90.1, 14 January 2019

- NPM: Handle package name with invalid characters

## v0.90.0, 14 January 2019

- Python: Bump poetry from 0.12.10 to 0.12.11 in /python/helpers
- Reorg dep

## v0.89.5, 13 January 2019

- .NET: Handle wildcard requirements without any digits

## v0.89.4, 12 January 2019

- Handle 403 forbidden responses from Bitbucket

## v0.89.3, 12 January 2019

- Ruby: Handle fetching gemspecs which specify a path

## v0.89.2, 11 January 2019

- Require composer from omnibus
- Update README for refactor install instructions
- PHP: Handle blank responses from registries
- Add composer to Dockerfile.ci and loadpath in dry-run

## v0.89.1, 11 January 2019

- Add missing requires

## v0.89.0, 11 January 2019

- PHP reorg
- Change subprocess IO.popen to Open3.capture2
- Add error context when helper subprocesses fail

## v0.88.3, 10 January 2019

- Ruby: Add Ruby 2.6.0 to list of rubies in RubyRequirementSetter
- Handle git dependencies when creating PR message for libraries

## v0.88.2, 10 January 2019

- JS: Handle ~ and ^ version requirements with blank minor.patch version

## v0.88.1, 9 January 2019

- Better handling of directories in changelog finder

## v0.88.0, 9 January 2019

- Elixir reorg

## v0.87.15, 9 January 2019

- PHP: Raise resolvability issue when working with local VCS errors
- Bump @dependabot/yarn-lib from 1.12.3 to 1.13.0 in /helpers/yarn

## v0.87.14, 9 January 2019

- Handle Bitbucket 401s during changelog lookup
- Handle Bitbucket 401s during commit lookup

## v0.87.13, 7 January 2019

- Cargo: If a file is both a support_file and a dependency file, treat as a dependency file only

## v0.87.12, 7 January 2019

- Cargo: Handle aliased dependencies better in file preparer
- Ruby: Handle subdependency updates when the subdep gets removed

## v0.87.11, 7 January 2019

- PHP: Cowardly ignore of stefandoorn/sitemap-plugin error we can't figure out
- PHP: Serve resolution error for non-https requests when they're disallowed
- PHP: Improve memory limit handling in PHP helper

## v0.87.10, 6 January 2019

- Better GitHub issue sanitization
- Gradle: Handle packaging types in versions

## v0.87.9, 5 January 2019

- Elixir: Handle whitespace before commas when updating mixfiles

## v0.87.8, 4 January 2019

- Python: Order additional hashes alphabetically when updating pip-compile files

## v0.87.7, 4 January 2019

- Docker: Reduce number of calls to Dockerhub when determining latest version

## v0.87.6, 4 January 2019

- Yarn: de-duplicate indirect dependencies

## v0.87.5, 4 January 2019

- Handle empty versions properly when a build or local version is possible

## v0.87.4, 3 January 2019

- Go (dep): Handle unreachable vanity URLs in parser

## v0.87.3, 3 January 2019

- .NET: Extend timeout for .NET repos
- Maven: More tests for versions that use multiple properties
- Maven: Handle properties with a suffix better

## v0.87.2, 3 January 2019

- Reduce the number of layers in the docker image

## v0.87.1, 2 January 2019

- Register GoModules::Requirement class
- Add go_modules package to Rakefile

## v0.87.0, 2 January 2019

- Go (modules): reorg
- JS: Handle requirements with an || when bumping versions

## v0.86.25, 2 January 2019

- Raise RepoNotFound errors when creating PRs
- Python: Don't treat post-releases as pre-releases

## v0.86.24, 1 January 2019

- Python: Augment hashes from pip-compile if necessary

## v0.86.23, 1 January 2019

- Bump rubygems and bundler versions

## v0.86.22, 1 January 2019

- Revert "Patch Rubygems requirement equality"
- Bump rubygems and bundler versions

## v0.86.21, 1 January 2019

- Ruby: Less strict requirement comparison
- Add TODO to Python pip_compile file updater

## Archived changes between 2017 and 2018

[Changelog archive 2017 to 2018](CHANGELOG_ARCHIVE_2017_TO_2018.md)
