# Dependabot Updater

This is an internal component that GitHub uses to run Dependabot, it's not
considered useful outside of this internal usage, and we also are currently not
considering any contributions to this part of the codebase to make it more
generic. We do however use it to run some end-to-end tests against the rest of
the codebase, so we can ensure that things still work when we deploy them.

This component communicates with an API that is only accessible inside the
GitHub network, and so is not generally accessible.

## Setup

You will need to provide the build a Personal Access Token to access the GitHub Package Registry to retrieve
dependency containers.

[Create a token](https://github.com/settings/tokens/new) with the `packages:read` scope and set it in your environment
as `GPR_TOKEN`

Run the setup script:

```
script/setup
```

## Tests

We run [rspec](https://rspec.info/) tests inside a Docker container for this project:

```
script/test
```

You can run an individual test file like so:

```
script/test spec/dependabot/integration_spec.rb
```

### VCR

In order to avoid network calls, we use [VCR](https://github.com/vcr/vcr) to maintain
fixtures for the remote services we interact with.

If you are adding a new test that makes network calls, please ensure you record a new fixture.

:warning: At time of writing, **our tests will not fail if a fixture is missing**. See: `spec/spec_helper.rb`

#### Recording new fixtures

If you've added a new test which has the `vcr: true` metadata, you can record a fixture for just those changes like so:

```
VCR=new_episodes DEPENDABOT_TEST_ACCESS_TOKEN=<redacted> script/test
```

`DEPENDABOT_TEST_ACCESS_TOKEN` will need to be a Personal Access Token with the full `repo` scope.

#### Updating existing fixtures

If you need to upadate existing fixtures, you can use the `all` flag like so:

```
VCR=all DEPENDABOT_TEST_ACCESS_TOKEN=<redacted> bundle exec rspec spec
```

As above, you will need a PAT with the full `repo` scope
