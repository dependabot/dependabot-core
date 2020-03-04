## `dependabot-docker`

Docker support for [`dependabot-core`][core-repo].

### Running locally

1. Install Ruby dependencies
   ```
   $ bundle install
   ```

2. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

## Description
This README provides details about unit testing of the conan updater dependabot code. Tests are written in `RSpec` framework https://relishapp.com/rspec. RSpec is a DSL for describing the expected behavior of Ruby code/software.

### Important note:

Instructions described here are only for unit tests, extra steps and configuration are needed to perform E2E integration tests.

## Pre-requisites

Below are the pre-requisites to execute tests:
* Install Ruby version `2.6.0` (or higher)
* Install Ruby bundler https://bundler.io

## Pre-requisites installation

After installation of Ruby bundler, execute the below command inside `concourse-docker-updater/concourse-docker` to install all the required packages:

```
bundle install --path requirements
```

## Executing tests

All RSpec files exist in `concourse/spec/dependabot/concourse`. Tests are executed inside the top `concourse` directory. Below is the command to execute tests:

WARNING: most of the tests will fail, until we merge Dependabot Docker and Concourse Docker Updater
Run all tests:
```shell
bundle exec rspec -f d
```
To run only the tests added by PCI team, as in terraform-tomato.git/github-automation-tools/concourse-docker-updater/concourse-docker/concourse/ repository, run the following:
```shell 
bundle exec rspec --tag pix4d
```

## Formatting Ruby files

WARNING: FORATING SHOULD NOT BE USED UNTIL IMPORETET RUBOCOP FILE IS IN SYNC WITH UPSTREAM SYTLE SETUP

`Rubocop` https://www.rubocop.org is a tool to format/lint Ruby files. It has `.rubocop.yml` configuration file to control which formatting checks to apply. Settings defined in this file will be applied to any `rubocop` command executed in the directory tree under `concourse-docker`, e.g. `concourse-docker/concourse`, `concourse-docker/concourse/spec`

To check the formatting of a file, execute:

```shell
bundle exec rubocop <filename>
```

To fix formatting bugs in a file use `-a` flag, e.g.

```shell
bundle exec rubocop -a <filename>
```

## Note:
The `-a` flag will apply the changes in place, i.e. it will override the file
