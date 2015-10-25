# Bump

[![Circle CI](https://circleci.com/gh/gocardless/bump.svg?style=svg&circle-token=135135b2c43b14edc2f5031621a3c1681caeb1c8)](https://circleci.com/gh/gocardless/bump)

Bump helps keep your project's Ruby and Node dependencies up to date. It:

- Checks for updates to each of your dependencies.
- Builds an updated dependency file for each update required.
- Opens a separate Pull Request for each update.

All that's left for you to do is review the change.

### Using Bump from your local machine

You can run Bump locally to kick-off a one-off update of your project's
dependencies. Bump will ask you for the project's repository and the language of
the dependencies you'd like to update.

1. Set up a local SQS compatible message queue. We use [fake_sqs](https://github.com/iain/fake_sqs):
  ```bash
  $ bundle exec fake_sqs
  ```

2. Create queues (persisted in memory only) for each of Bump's services:
  ```bash
  $ bundle exec ./set_up_sqs_queues.rb
  ```

3. Start a worker for each queue. We use [foreman](http://ddollar.github.io/foreman/) to automate the process:
  ```bash
  $ bundle exec foreman start
  ```

4. Push a job to `DependencyFileFetcher` (the first of Bump's services):
  ```bash
  $ bundle exec ./bump_dependencies_for_repo.rb
  ```

## Contributing

We'd love to see the following improvements to Bump:

- A straightforward deployment process, make it easy for anyone to self-host
  the project (and automatically trigger an update check every day)
- A faster `DependencyFileUpdater` for Node. This might need its own,
  language-specific worker that borrows from NPM internals to avoid doing an
  actual install.
- Support for more languages (Python should be relatively easy?)

### Project structure

Bump is split into five concerns, each of which have their own worker which runs
as a separate service:

| Service                 | Description                                                                                   |
|-------------------------|-----------------------------------------------------------------------------------------------|
| `DependencyFileFetcher` | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `DependencyFileParser`  | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `UpdateChecker`         | Checks whether a given dependency is up-to-date.                                              |
| `DependencyFileUpdater` | Updates a dependency file to use the latest version of a given dependency.                    |
| `PullRequestCreator`    | Creates a Pull Request to the original repo with the updated dependency file.                 |
