<p align="center">
  <img src="https://s3.eu-west-2.amazonaws.com/dependabot-images/logo-with-name-horizontal.svg?v4" alt="Dependabot" width="336">
</p>

# Dependabot Core [![Dependabot Status][dependabot-status]][dependabot]

Dependabot Core is the heart of [Dependabot][dependabot]. It handles the logic
for updating dependencies on GitHub (including GitHub Enterprise) and GitLab. We
plan to add support for Bitbucket and Azure DevOps in the future, too.

If you want to host your own automated dependency update bot then this repo
should give you the tools you need. A reference implementation is available
[here][dependabot-script].

## What's in this repo?

Dependabot Core is a collection of packages for automating dependency updating
in Ruby, JavaScript, Python, PHP, Elixir, Elm, Go, Rust, Java and
.NET. It can also update git submodules, Docker files and Terraform files.
Highlights include:

- Logic to check for the latest version of a dependency *that's resolvable given
  a project's other dependencies*
- Logic to generate updated manifest and lockfiles for a new dependency version
- Logic to find changelogs, release notes, and commits for a dependency update

## Other Dependabot resources

In addition to this library, you may be interested in:

- The [dependabot-script][dependabot-script] repo, which provides a collection
  of scripts that use this library to update dependencies on GitHub Enterprise
  or GitLab
- The [API docs][api-docs] for Dependabot's hosted instance (dependabot.com)

## Setup

To run all of Dependabot Core, you'll need Ruby, Python, PHP, Elixir, Node, Go,
Elm and Rust installed. However, if you just wish to run it for a single
language you can get away with just having that language and Ruby.

The main library is written in Ruby, while JavaScript, Python, PHP, Elm,
Elixir, Go and Rust are required for dealing with updates for their respective
languages.

To install the helpers for each language:

1. `cd npm_and_yarn/helpers && yarn install --production && cd -`
2. `cd composer/helpers && composer install --no-dev && cd -`
3. `cd python/helpers && pyenv exec pip install -r requirements.txt && cd -`
4. `cd elixir/helpers && mix deps.get && cd -`

## Architecture

Dependabot Core is a collection of Ruby packages (gems), which contain the
logic for updating dependencies in a number of languages.

### `dependabot-common`

The `common` package contains all general-purpose / shared functionality. For
instance the code for creating pull requests via GitHub's API lives here, as
does most of the logic for handling Git dependencies (as most languages support
Git dependencies in one way or another). There are also base classes defined for
each of the major concerns required to implement support for a language or
package manager.

### `dependabot-{package-manager}`

There is a gem for each package manager or language that Dependabot
supports. At a minimum, each of these gems will implement the following
classes:

| Service          | Description                                                                                   |
|------------------|-----------------------------------------------------------------------------------------------|
| `FileFetcher`    | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). See the [README](https://github.com/dependabot/dependabot-core/blob/master/common/lib/dependabot/file_fetchers/README.md) for more details. |
| `FileParser`     | Parses a dependency file and extracts a list of dependencies for a project. See the [README](https://github.com/dependabot/dependabot-core/blob/master/common/lib/dependabot/file_parsers/README.md) for more details. |
| `UpdateChecker`  | Checks whether a given dependency is up-to-date. See the [README](https://github.com/dependabot/dependabot-core/tree/master/common/lib/dependabot/update_checkers/README.md) for more details. |
| `FileUpdater`    | Updates a dependency file to use the latest version of a given dependency. See the [README](https://github.com/dependabot/dependabot-core/tree/master/common/lib/dependabot/file_updaters/README.md) for more details. |
| `MetadataFinder` | Looks up metadata about a dependency, such as its GitHub URL. See the [README](https://github.com/dependabot/dependabot-core/tree/master/common/lib/dependabot/metadata_finders/README.md) for more details. |
| `Version`        | Describes the logic for comparing dependency versions. See the [hex Version class](https://github.com/dependabot/dependabot-core/blob/master/hex/lib/dependabot/hex/version.rb) for an example. |
| `Requirement`    | Describes the format of a dependency requirement (e.g. `>= 1.2.3`). See the [hex Requirement class](https://github.com/dependabot/dependabot-core/blob/master/hex/lib/dependabot/hex/requirement.rb) for an example. |

The high level flow looks like this:

<p align="center">
  <img src="https://s3.eu-west-2.amazonaws.com/dependabot-images/package-manager-architecture.svg" alt="Dependabot architecture">
</p>

### `dependabot-omnibus`

This is a "meta" gem, that simply depends on all the others. If you want to
automatically include support for all languages, you can just include this gem
and you'll get all you need.

It also includes a "dry-run" script that can be used to run a dependency update
job, printing the diff that would be generated to the terminal. It takes two
positional arguments: the package manager and the GitHub repo name (including
the account):

```bash
$ cd omnibus
$ bundle exec ruby bin/dry-run.rb go_modules rsc/quote
=> fetching dependency files
=> parsing dependency files
=> updating 2 dependencies
...
```


## Why is this public?

As the name suggests, Dependabot Core is the core of Dependabot (the rest of the
app is pretty much just a UI and database). If we were paranoid about someone
stealing our business then we'd be keeping it under lock and key.

Dependabot Core is public because we're more interested in it having an
impact than we are in making a buck from it. We'd love you to use
[Dependabot][dependabot], so that we can continue to develop it, but if you want
to build and host your own version then this library should make doing so a
*lot* easier.

If you use Dependabot Core then we'd love to hear what you build!

## License

We use the License Zero Prosperity Public License, which essentially enshrines
the following:
- If you would like to use Dependabot Core for non-commercial purposes, such as
  to host a bot at your workplace, then we give you full permission to do so. In
  fact, we'd love you to, and will help and support you however we can.
- If you would like to add Dependabot's functionality to your for-profit
  company's offering then we DO NOT give you permission to use Dependabot Core
  to do so. Please contact us directly to discuss a partnership or licensing
  arrangement.

If you make a significant contribution to Dependabot Core then you will be asked
to transfer the IP of that contribution to Dependabot Ltd so that it can be
licensed in the same way as the above.

## History

Dependabot and Dependabot Core started life as [Bump][bump] and
[Bump Core][bump-core], back when Harry and Grey were working at
[GoCardless][gocardless]. We remain grateful for the help and support of
GoCardless in helping make Dependabot possible - if you need to collect
recurring payments from Europe, check them out.

[dependabot]: https://dependabot.com
[dependabot-status]: https://api.dependabot.com/badges/status?host=github&identifier=93163073
[dependabot-script]: https://github.com/dependabot/dependabot-script
[api-docs]: https://github.com/dependabot/api-docs
[bump]: https://github.com/gocardless/bump
[bump-core]: https://github.com/gocardless/bump-core
[gocardless]: https://gocardless.com
