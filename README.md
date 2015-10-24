# Bump

[![Circle CI](https://circleci.com/gh/gocardless/bump.svg?style=svg&circle-token=135135b2c43b14edc2f5031621a3c1681caeb1c8)](https://circleci.com/gh/gocardless/bump)

Bump helps keep your project's dependencies up to date by doing the manual work for you:

- Checks for updates to each of your dependencies every day.
- Builds an updated dependency file for each update required.
- Opens a separate Pull Request for each update.

All that's left for you to do is review the change.

## Supported languages

Bump is designed to work for many languages. Currently it supports:

- Ruby
- Node (in a feature branch)

## Project structure

Bump is split into five concerns, each of which runs as a separate service:

| Service                 | Description                                                                                   |
|-------------------------|-----------------------------------------------------------------------------------------------|
| `DependencyFileFetcher` | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `DependencyFileParser`  | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `UpdateChecker`         | Checks whether a given dependency is up-to-date.                                              |
| `DependencyFileUpdater` | Updates a dependency file to use the latest version of a given dependency.                    |
| `PullRequestCreator`    | Creates a Pull Request to the original repo with the updated dependency file.                 |

## Running locally

1. Get set up with SQS
  ```bash
  fake_sqs
  ```

2. Create the right queues and push a job to `bump-repos_to_fetch_files_for`
  ```ruby
  bundle exec ./test_produce.rb
  ```


3. Run [`foreman`](http://ddollar.github.io/foreman/)
  ```bash
  foreman start
  ```
