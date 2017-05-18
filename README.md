# Bump Core

Bump Core is a library containing the logic to keep a project's Ruby,
JavaScript, Python and Cocoa dependencies up to date. It is used by applications
like [gocardless/bump](https://github.com/gocardless/bump) and
[Dependabot](https://dependabot.com).

## Setup

To run Bump Core, you'll need both Ruby and Node installed. The main library is
written in Ruby, and JavaScript is required for dealing with package.json and
yarn.lock files.

Before running Bump Core, install dependencies for the core library and the
helpers:

1. `bundle install`
2. `cd helpers/javascript && yarn install && cd -`

## Internals

Bump Core has helper classes for six concerns:

| Service                        | Description                                                                                   |
|--------------------------------|-----------------------------------------------------------------------------------------------|
| `Bump::DependencyFileFetchers` | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `Bump::DependencyFileParsers`  | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `Bump::UpdateCheckers`         | Checks whether a given dependency is up-to-date.                                              |
| `Bump::DependencyFileUpdaters` | Updates a dependency file to use the latest version of a given dependency.                    |
| `Bump::PullRequestCreator`     | Creates a Pull Request to the original repo with the updated dependency file.                 |
| `Bump::PullRequestUpdater`     | Updates an existing Pull Request with new dependency files (e.g., to resolve conflicts).      |

## Contributing

We'd love to see the following improvements to Bump Core:

- Support for [Pipenv](https://github.com/kennethreitz/pipenv) in Python.
- Support for [npm5](https://www.npmjs.com/package/npm5) in JavaScript.
- Support for additional languages (Elixir, anyone?)

---

GoCardless ♥ open source. If you do too, come [join us](https://gocardless.com/about/jobs/software-engineer/).
