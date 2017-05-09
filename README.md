# Bump Core

Bump Core is a library containing the logic to keep a project's Ruby,
JavaScript and Python dependencies up to date. It is used by applications like
[gocardless/bump](https://github.com/gocardless/bump).

# The code / contributing

Bump Core has helper classes for five concerns:

| Service                        | Description                                                                                   |
|--------------------------------|-----------------------------------------------------------------------------------------------|
| `Bump::DependencyFileFetchers` | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `Bump::DependencyFileParsers`  | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `Bump::UpdateCheckers`         | Checks whether a given dependency is up-to-date.                                              |
| `Bump::DependencyFileUpdaters` | Updates a dependency file to use the latest version of a given dependency.                    |
| `Bump::PullRequestCreator`     | Creates a Pull Request to the original repo with the updated dependency file.                 |

### Contributing

We'd love to see the following improvements to Bump Core:

- A faster `DependencyFileUpdater` for JavaScript. This might need its own,
  language-specific worker that borrows from NPM internals to avoid doing an
  actual install.

---

GoCardless ♥ open source. If you do too, come [join us](https://gocardless.com/about/jobs/software-engineer/).
