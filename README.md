# Bump

[![Build Status](https://travis-ci.org/gocardless/bump.svg?branch=master)](https://travis-ci.org/gocardless/bump)

Bump helps you keep your project's Ruby and Node dependencies up to date. It:

- Checks for updates to each of your dependencies.
- Builds an updated dependency file for each update required.
- Opens a separate Pull Request for each update.

All that's left for you to do is review the change.

### Using Bump from your local machine

You can run Bump locally to kick-off a one-off update of your project's
dependencies. Bump will ask you for the project's repository and the language of
the dependencies you'd like to update.

1. Pull down bump and install its dependencies:
  ```bash
  git clone git@github.com:gocardless/bump.git  # Pull down Bump
  cd bump && bundle install                     # Install Bump's dependencies
  cp config/dummy_env .env                      # Set up your environment

  # You'll also need to update the `BUMP_GITHUB_TOKEN` in .env to be a valid
  # token with access to your project and any private dependencies
  ```

2. Set up a local SQS compatible message queue. We use [fake_sqs](https://github.com/iain/fake_sqs):
  ```bash
  bundle exec fake_sqs
  ```

3. In a new window, create queues (persisted in memory only) for each of Bump's services:
  ```bash
  bundle exec bin/set_up_sqs_queues
  ```

4. Start a worker for each queue. We use [foreman](http://ddollar.github.io/foreman/) to automate the process:
  ```bash
  bundle exec foreman start
  ```

5. In a new window, push a message to `DependencyFileFetcher` (the first of Bump's services):
  ```bash
  bundle exec bin/bump_dependencies_for_repo
  ```

### Hosting bump on AWS

Bump is designed to be easily deployed to AWS's Elastic Container Service (ECS)
so you can set it up to run daily. More details TBC.

# The code / contributing

To allow support for multiple languages Bump has a service-oriented
architecture. It can be split into five concerns, each of which has its own
worker:

| Service                 | Description                                                                                   |
|-------------------------|-----------------------------------------------------------------------------------------------|
| `DependencyFileFetcher` | Fetches the relevant dependency files for a project (e.g., the `Gemfile` and `Gemfile.lock`). |
| `DependencyFileParser`  | Parses a dependency file and extracts a list of dependencies for a project.                   |
| `UpdateChecker`         | Checks whether a given dependency is up-to-date.                                              |
| `DependencyFileUpdater` | Updates a dependency file to use the latest version of a given dependency.                    |
| `PullRequestCreator`    | Creates a Pull Request to the original repo with the updated dependency file.                 |

### Contributing

We'd love to see the following improvements to Bump:

- A straightforward deployment process, make it easy for anyone to self-host
  the project (and automatically trigger an update check every day)
- A faster `DependencyFileUpdater` for Node. This might need its own,
  language-specific worker that borrows from NPM internals to avoid doing an
  actual install.
- Support for more languages (Python should be relatively easy?)

---

GoCardless ♥ open source. If you do too, come [join us](https://gocardless.com/jobs#software-engineer).
