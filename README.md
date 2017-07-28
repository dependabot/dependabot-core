# Dependabot Core

Dependabot Core is a library containing the logic to keep a project's
dependencies up to date. It is used by [Dependabot](https://dependabot.com).

## Setup

To run Dependabot Core, you'll need Ruby, Python, PHP and Node installed. The
main library is written in Ruby, while JavaScript, Python and PHP are required
for dealing with updates for their respective languages.

Before running Dependabot Core, install dependencies for the core library and
the helpers:

1. `bundle install`
2. `cd helpers/javascript && yarn install && cd -`
3. `cd helpers/php && composer install && cd -`
4. `pip install pip==9.0.1`

## Internals

Dependabot Core has helper classes for seven concerns:

| Service                    | Description                                                                                   |
|----------------------------|-----------------------------------------------------------------------------------------------|
| `Dependabot::FileFetchers`       | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `Dependabot::FileParsers`        | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `Dependabot::UpdateCheckers`     | Checks whether a given dependency is up-to-date.                                              |
| `Dependabot::FileUpdaters`       | Updates a dependency file to use the latest version of a given dependency.                    |
| `Dependabot::MetadataFinders`    | Looks up metadata about a dependency, such as its GitHub URL.                                 |
| `Dependabot::PullRequestCreator` | Creates a Pull Request to the original repo with the updated dependency file.                 |
| `Dependabot::PullRequestUpdater` | Updates an existing Pull Request with new dependency files (e.g., to resolve conflicts).      |

## History

Dependabot and Dependabot Core started life as [Bump][bump] and
[Bump Core][bump-core], back when Harry and Grey were working at
[GoCardless][gocardless]. We remain grateful for the help and support of
GoCardless in helping make Dependabot possible - if you need to collect
recurring payments from Europe, check them out.

## Contributing

We'd love to see the following improvements to Dependabot Core:

- Support for Python's upcoming [Pipfile](https://github.com/pypa/pipfile).
- Support for [npm5](https://www.npmjs.com/package/npm5) in JavaScript.
- Support for additional languages (Elixir, anyone?)

[bump]: https://github.com/gocardless/bump
[bump-core]: https://github.com/gocardless/bump-core
[gocardless]: https://gocardless.com
