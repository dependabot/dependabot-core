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
