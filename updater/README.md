# Dependabot Updater

This is an internal component that GitHub uses to run Dependabot, it's not
considered useful outside of this internal usage, and we also are currently not
considering any contributions to this part of the codebase to make it more
generic. We do however use it to run some end-to-end tests against the rest of
the codebase, so we can ensure that things still work when we deploy them.

This component communicates with an API that is only accessible inside the
GitHub network, and so is not generally accessible.

## Setup

To work with the updater, you will need to build the bundler image using the
build script in this directory:

```bash
script/build
```

## Tests

We run [rspec](https://rspec.info/) tests inside a Docker container for this project:

```bash
script/test
```

You can run an individual test file like so:

```bash
script/test spec/dependabot/integration_spec.rb
```

A small number of tests hit the GitHub API, so you will need to set the envvar
`DEPENDABOT_TEST_ACCESS_TOKEN` with a Personal Access Token with the full `repo`
scope.

```bash
export DEPENDABOT_TEST_ACCESS_TOKEN=ghp_xxx
```

### VCR

In order to avoid network calls, we use [VCR](https://github.com/vcr/vcr) to maintain
fixtures for the remote services we interact with.

If you are adding a new test that makes network calls, please ensure you record a new fixture.

:warning: At time of writing, **our tests will not fail if a fixture is missing**. See: `spec/spec_helper.rb`

#### Recording new fixtures

If you've added a new test which has the `vcr: true` metadata, you can record a fixture for just those changes like so:

```
VCR=new_episodes script/test
```

#### Updating existing fixtures

If you need to upadate existing fixtures, you can use the `all` flag like so:

```
VCR=all script/test
```
