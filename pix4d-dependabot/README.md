# Dependabot: General information, development and usage

Dependabot is a tool that takes care of your project dependency updates in an automated way. It does so by creating pull requests to keep your dependencies secure and up-to-date. Dependabot pulls down your dependency files and looks for any outdated or insecure requirements. If any of your dependencies are out-of-date, Dependabot opens individual pull requests to update each one.

We can use Dependabot:
- as a Github application, which is a free, hosted and feature-rich dependency updater
- by using Dependabot Core. This is the approach taken by PCI team

As the name suggest  Dependabot Core is the heart of [Dependabot](https://dependabot.com/). It  handles the logic for updating dependencies on GitHub, GitLab, and Azure DevOps. Hosting your own automated dependency update bot requires the use of the reference implementation (available [here](https://github.com/dependabot/dependabot-script)). Currently the PCI team uses only the Docker package manager.
Some additional package managers that could be useful for the team: Ruby, Python, Go, Terraform

### Dependabot workflow/components:

File Fetcher - File Parser - Update Checker - File Updater - PR creator

Periodically triggered Concourse job, it fetches the Dockerfile that is monitored (_File Fetcher_), parses the _FROM_ line in the Dockerfile (_File Parser_) to find the tag of the Docker image used. It further checks (_Update Checker_) if a newer tag (update) is available in Docker registry. If yes it updates the Docker file (_File Updater_) and opens a new pull request in the repository (_PR creator_). In short, it proposes the updates of base Docker images used in the Dockerfile.

Figure: Example of a PR opened by Dependabot in linux-image-build repository
![](dependabot_pr_example.png?raw=true "PR opened by Dependabot")

*Problem*:
In Pix4D, Concourse runs all Linux jobs and all the resources in Linux containers (Docker images) which we would like to keep up to date. From the experience we know that using tag “latest” often leads to broken pipelines, while pinning the tag and manually updating it can lead to using too old Docker images across many pipelines. Therefore we needed an automated dependency updater like Dependabot but for yaml files.

Unfortunately, at this moment Depenabot Docker package manager can only fetch and parse Dockerfiles. This is quite a limitation, since in Pix4D we mostly use Docker images in Concourse pipelines by configuring the Docker image repository name (name and tag) in pipeline templates yml files. In the below example we use the Docker image _cpp-builder-ubuntu-18.04_ with a pinned tag in the format _YYYYMMDDHHMMSS_

```
---
  resources:
  - name: builder-ubuntu-18.04.docker
    type: registry-image
    source:
      username: pix4d
      password: ((docker_cloud_pix4d_password))
      repository: docker.ci.pix4d.com/cpp-builder-ubuntu-18.04
      tag: 20200820101141
```

To enable automatic updates for Docker image tags by actually updating the Concourse pipeline template file instead of Dockerfiles we modified the Docker package manager in Dependabot core, by maintaining our own fork of [Dependabot Core](https://github.com/Pix4D/dependabot-core) Github repository.

## Pix4D fork workflow

Difference: dependabot docker package manager is modified to allow us to update Docker image tags in Concourse pipeline template files.

Added by PCI team:

- [`ci`](https://github.com/Pix4D/dependabot-core/tree/master/ci) directory containing pipeline template, settings and task files

- [Dockerfile](https://github.com/Pix4D/dependabot-core/blob/master/Dockerfile.pix4d) to build our own Docker image

- [pix4d-dependabot module](https://github.com/Pix4D/dependabot-core/blob/master/pix4d-dependabot/) containing the main Dependabot script and helper functions.

- code and tests changes only for docker package manager. List of files modified by PCI team can be found by executing:

```
git log --pretty="%H" --author="Pix4D" | while read commit_hash; do git show --oneline --name-only $commit_hash | tail -n+2; done | sort | uniq
```

[MASTER PIPELINE](https://builder.ci.pix4d.com/teams/developers/pipelines/dependabot-master)
contains two jobs:
- test-dependabot
- merge-upstream

### AUTOMATED WORKFLOW

1. merge-upstream job is automatically triggered
    * fetches a new upstream version
    * verify that all checks jobs finished successfully in the upstream repository
    * creates a feature branch in the forked repository
    * merges upstream changes
    * creates a PR in the forked repository
       - PR title: [no-changes-to-pix4d-dependabot] - no review needed. If tests are passing, this PR will be automerged in later steps
       - PR title: [changes-to-pix4d-dependabot] - more detailed review required. Review is necessary only for files in the `docker` folder and the `Dockerfile`. Suggestion: filter them in Github GUI

2. The depenabot-core repository is monitored by set-pipeline job in Github-automation-tools pipeline - since the new PR is opened by the merge-upstream job, PR resource detects it, sets a new featured pipeline, writes a comment in the PR with the pipeline URL and triggers the test-dependabot job

3. Test-dependabot job build the `pix4d-depenadabot` Docker image and pushes it to Pix4D Docker registry. During the build phase we run unit tests that contain both upstream tests and our Pix4D modifications. Additionally it also runs rubocop a Ruby static code analyzer and code formatter.

4. If Docker images is succesfully built and pushed to registry and the PR title is [no-changes-to-pix4d-dependabot], the PR is automerged. Otherwise PR needs to get 2 approvals from PCI team members. Afterwhich, it can be merged to the master branch

Recently (August 2020), Github actions were activated in the upstream repository. The Github actions are disabled for Pix4D forked repository, so we added a step in the merge-upstream pipeline job to verify all the checks are passing upstream. If any of the checks fail upstream we do not merge the upstream changes into Pix4D forked repository.

_CASE:_ upstream changes are merged in the feature branch, PR is opened, but the tests (rspec for `docker` package manager or rubocop) fail. What should I do?

_SOLUTION_ locally fetch the branch, fix the error, add a new commit, run the tests again. After the PR is approved and the test job is green again, merge the PR.

## Development and unit tests
Tests are written in `RSpec` framework https://relishapp.com/rspec. RSpec is a DSL for describing the expected behavior of Ruby code/software.

## Pre-requisites

Below are the pre-requisites to execute tests:
* Install Ruby version `2.7.0` (or higher)
* Install Ruby bundler https://bundler.io

## Pre-requisites installation
*NOTE*: This is a equivalent step to running `pip install -r requirements.txt`

After installation of Ruby bundler, execute the below command inside `pix4d-dependabot` module to install all the required packages:

```
bundle config set path '../../requirements'
bundle install
```

## Executing tests

All RSpec files exist in `docker/spec` and `pix4d-dependabot/spec`. Tests are executed inside the `docker` or inside `pix4d-dependabot` directory. Below is the command to execute tests:

Navigate to `docker` directory:
```shell
cd docker
```

Run all tests:
```shell
bundle exec rspec -f d
```

and repeat the same for the `pix4d-dependabot` directory.

To run only the tests added by PCI team, run the following command:
```shell
bundle exec rspec --tag pix4d
```

## Possible improvments to Pix4D Dependabot

- enable updating Docker images used in Concourse task files
- enable using Dependabot in docker mode without auto-merging (partially)

## Formatting Ruby files

`Rubocop` https://www.rubocop.org is a tool to format/lint Ruby files. It has `.rubocop.yml` configuration file to control which formatting checks to apply. Settings defined in this file will be applied to any `rubocop` command executed in the repository directory tree.

To check the formatting of all Ruby files in the repository, from `docker` directory execute:

```shell
bundle exec rubocop -c ../.rubocop.yml ../
```
or only a single file:
```shell
bundle exec rubocop -c ../.rubocop.ym <filename>
```

To fix formatting bugs in a file use `-a` flag, e.g.

```shell
bundle exec rubocop -a <filename>
```
*NOTE*: The `-a` flag will apply the changes in place, i.e. it will override the file

## CONFIGURATION

The Pix4D Dependabot main script (bot) calling each of the Dependabot main components (file fetcher, file parser, update checker, file updater and PR creator) can be found [here](https://github.com/Pix4D/dependabot-core/blob/master/pix4d-dependabot/pix4d-dependabot.rb). The script is configured using the following list of environmental variables:

*GITHUB_ACCESS_TOKEN* - personal access token for authentication to GitHub (in the CI we use the token for the Pix4D-Janus user). The user needs to have read and write access to the repository.

*REPOSITORY_DATA* list of dictionaries, where each dictionary should contain the following keys:
   - *module* i.e `docker`, `concourse`, `pip`. Selecting the `concourse` option, we will parse the pipeline template _yml_ file. Selecting the `docker` option, the script will recursively find all Dockerfiles in the repository below a paths set by: *dependency_dirs* and for each file, it will propose an update of the base Docker image used in each of the Dockerfiles. Selecting the `pip` option will update your Python dependency files. In example `Pipfile`, `Pipfile.lock` and `requirements.txt` files.
   - *repo* i.e. Pix4D/test-dependabot-python name of the Github repository (containing the organization name) i.e. `Pix4D/test-dependabot-docker`
   - *branch* Github repository branch i.e master, staging
   - *dependency_dirs* i.e. ["/"", "ci/docker", "ci/pipelines/"", "project/requirements"] list of paths in the Github repository where the files we want to parse can be found: i.e. `/dockerfiles/`,`/ci/pipelines/`, `/python_package` or Github root directory `/`.
   - *lockfile_only* (optional) i.e. Update only lockfiles. Defaults to true in case of Pip module
    and false in case of Docker module

### REQUIRED CONFIGURATION DEPENDING ON MODULE:

#### PYTHON MODULE
*ARTIFACTORY_USERNAME* - username to use when authenticating to Pix4D Artifactory.

*ARTIFACTORY_PASSWORD* - password to use when authenticating to Pix4D Artifactory.

*EXTRA_INDEX_URL* - extra index url i.e https://artifactory.ci.pix4d.com/artifactory/api/pypi/pix4d-pypi-local/simple/

#### DOCKER/CONCOURSE MODULE
The following must be set when we want to update Docker images from private Docker registry, otherwise, these can be considered as optional parameters:

*DOCKER_REGISTRY* - private Docker registry i.e. `docker.ci.pix4d.com`

*DOCKER_USER* - username to use when authenticating to the private Docker registry.

*DOCKER_PASS* - password to use when authenticating to the private Docker registry.


We currently run dependabot in all three mods:
- `docker` (updates base image of a Dockerfile): used in [linux-image-build] repository to update the tag for the base images in all Dockerfiles that can be found in the repository. The PR that is opened, is also immediately auto-merged by the bot.

- `concourse` (updates Docker image tags for each Dockerfile in Concourse pipeline template yml file): for all other repositories set in github-automation-tools [configuration file](https://github.com/Pix4D/terraform-tomato/blob/master/ci/github-automation-tools/pipeline_generator/repositories.yml). For each project that activated `docker: true` option we have one job in [github-automation-master](https://builder.ci.pix4d.com/teams/main/pipelines/github-automation-master) pipeline running a Dependabot configured in concourse mode for this exact project/repository

- `pip` updates Python dependency files i.e `Pipfile`, `Pipfile.lock` and `requirements.txt` files. Mostly used by the `cloud team` and it is configured in [configuration file](https://github.com/Pix4D/terraform-tomato/blob/master/ci/github-automation-tools/pipeline_generator/repositories.yml).


## USAGE

### Example 1

Concourse job running Dependabot in concourse mode for [github-automation-playground] Github repository. This configuration will:

- fetch any file with `/template/` as a part of the filename under found in `ci/pipelines/`

- parse the template file under the resource key of type `registry-image` to find all the Docker images (`source: repository`) and their tags (`source: tag`)

- check if a newer tag exists in the Docker repository. The repository in which to check is determined from the value set in `source: repository` key. Tag `latest` is always skipped, while the tag `bootstrapme` is alway updated to the newest tag in the format `YYYYMMDDHHMMSS`

- if newer tag is found the template file is updated

- a new PR in [github-automation-playground] repository is created, proposing the update of the tag. PR is opened against the branch set by `REPOSITORY_BRANCH` environmental variable (defaults to master)

*IMPORTANT:* The user for which the `GITHUB_ACCESS_TOKEN` is set needs to have read and write access to the repository.

```
---
jobs:
- name: docker-updater-github-automation-playground
 max_in_flight: 1
 plan:
 - task: pipeline-docker-update
   config:
     platform: linux
     image_resource:
       type: registry-image
       source:
         repository: docker.ci.pix4d.com/pix4d-dependabot
         tag: latest
         username: pix4d
         password: ((docker_cloud_pix4d_password))
     run:
       path: /bin/sh
       args:
       - -c
       - |
         cd /home/dependabot/pix4d-dependabot/
         bundle exec ruby pix4d-dependabot.rb
   params:
      GITHUB_ACCESS_TOKEN:  ((janus_developers_rw_token))
      DOCKER_REGISTRY: docker.ci.pix4d.com
      DOCKER_USER: ((docker_cloud_pix4d_user))
      DOCKER_PASS: ((docker_cloud_pix4d_password))
      REPOSITORY_DATA:
      - branch: master
        dependency_dirs:
        - ci/pipelines/
        module: concourse
        repo: Pix4D/github-automation-playground
```

### Example 2

Concourse job running Dependabot in dependabot mode for [linux-image-build] Github repository. This configuration will:

- recursively find all the Dockerfiles under the path `dockerfiles/`

- fetch each of the Dockerfile

- parse the _FROM_ line in the Dockerfile to determine the base Docker image used and its tag

- check if a newer tag exists in the Docker repository. If newer tag is found the _FROM_ line in the Dockerfile file is updated

- a new PR in [linux-image-build] repository is created, proposing the update of the tag. PR is opened against the branch set by `REPOSITORY_BRANCH` environmental variable (defaults to `master`). The PR will be auto merged immediately, with no human interaction needed.


*IMPORTANT:* The user for which the `GITHUB_ACCESS_TOKEN` is set needs to have admin access to the repository, to be able to auto-merge and bypass any master branch protection rules that are set in place (i.e. PR reviews required)

```
---
jobs:
- name: dependabot-linux-image-build
 max_in_flight: 1
 plan:
 - task: pipeline-docker-update
   config:
     platform: linux
     image_resource:
       type: registry-image
       source:
         repository: docker.ci.pix4d.com/pix4d-dependabot
         tag: latest
         username: pix4d
         password: ((docker_cloud_pix4d_password))
     run:
       path: /bin/sh
       args:
       - -c
       - |
         cd /home/dependabot/pix4d-dependabot/
         bundle exec ruby pix4d-dependabot.rb
   params:
      GITHUB_ACCESS_TOKEN:  ((janus_developers_rw_token))
      DOCKER_REGISTRY: docker.ci.pix4d.com
      DOCKER_USER: ((docker_cloud_pix4d_user))
      DOCKER_PASS: ((docker_cloud_pix4d_password))
      REPOSITORY_DATA:
      - branch: docker
        dependency_dirs:
        - dockerfiles/
        module: concourse
        repo: Pix4D/linux-image-build
```

### Example 3

Concourse job running Dependabot in pip mode for [github-automation-playground] Github repository. This configuration will:

- fetch and parse any Python dependency files i.e `Pipfile` and `Pipfile.lock` in `python/pip_example` on `master` branch. Since in this case we have set `lockfile_only: false` both `Pipfile` and `Pipfile.lock` can be updated.

- fetch and parse any Python dependency files i.e `Pipfile` and `Pipfile.lock` in `python/pip_example` and `python/multiple_dep_single_file` on `staging` branch

- check if any of dependencies given in either `Pipfile` or `Pipfile.lock` files can be updated

- if any of the files can be updated, a new PR in [github-automation-playground] repository is created, proposing the update of the dependencies. PRs are opened against the `master` and `staging` branches

*IMPORTANT:* The user for which the `GITHUB_ACCESS_TOKEN` is set needs to have read and write access to the repository.

```
---
jobs:
- name: dependabot-linux-image-build
 max_in_flight: 1
 plan:
 - task: pipeline-docker-update
   config:
     platform: linux
     image_resource:
       type: registry-image
       source:
         repository: docker.ci.pix4d.com/pix4d-dependabot
         tag: latest
         username: pix4d
         password: ((docker_cloud_pix4d_password))
     run:
       path: /bin/sh
       args:
       - -c
       - |
         cd /home/dependabot/pix4d-dependabot/
         bundle exec ruby pix4d-dependabot.rb
   params:
      GITHUB_ACCESS_TOKEN:  ((janus_developers_rw_token))
      ARTIFACTORY_PASSWORD: ((concourse_artifactory_password))
      ARTIFACTORY_USERNAME: concourse
      EXTRA_INDEX_URL: https://artifactory.ci.pix4d.com/artifactory/api/pypi/pix4d-pypi-local/simple/
      REPOSITORY_DATA:
      - branch: master
        dependency_dirs:
        - python/pip_example
        lockfile_only: false
        module: pip
        repo: Pix4D/github-automation-playground
      - branch: staging
        dependency_dirs:
        - python/pip_example
        - python/multiple_dep_single_file
        module: pip
        repo: Pix4D/github-automation-playground
```

[Pix4D-core-repo]: https://github.com/Pix4D/dependabot-core
[linux-image-build]: https://github.com/Pix4D/linux-image-build/
[github-automation-playground]: https://github.com/Pix4D/github-automation-playground
