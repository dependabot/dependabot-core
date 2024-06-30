# dependabot-silent

This ecosystem is used for integration testing the `updater` code. See `tests/testdata` for the actual tests.

## Why

The `updater` code has been difficult to test. In the past we've had a large rspec test which used fixtures, and used actual ecosystems to test against. The fixtures made it hard to see the test as-a-whole, and having to rely on testing against specific ecosystems meant we were testing more than we needed. Also, the ecosystems were making actual network calls, sometimes due to native helpers which cannot be mocked.

The solution was to create a new ecosystem for testing, one that made no network calls, thus the name "silent".

It's a minimal implementation of an ecosystem which uses files containing JSON as the listing of available versions.

## How to read the tests

The tests are based on https://rsc.io/script and use text files in the txtar format to define all files involved in the test.

At the top of the test, there will be a [Dependabot CLI](https://github.com/dependabot/cli) command to run an update:

```bash
dependabot update -f input.yml --local . --updater-image ghcr.io/dependabot/dependabot-updater-silent
```

This will be followed by commands which assert expectations:

```bash
pr-created expected.json
```

The rest of the file defines which files are on-disk at the time of execution, so you'll have a manifest file for the silent ecosystem:

```json
-- manifest.json --
{
  "dependency-a": { "version": "1.2.3" }
}
```

The expected PR output (used in the `pr-created` command above)

```json
-- expected.json --
{
  "dependency-a": { "version": "1.2.5" }
}
```

The files which the silent ecosystem uses to tell what versions are available:

```json
-- dependency-a --
{
  "versions": [
    "1.2.3",
    "1.2.4",
    "1.2.5"
  ]
}
```

And finally the input file used in the `dependabot` command at the start of the test:

```yml
-- input.yml --
job:
  package-manager: "silent"
  source:
    directory: "/"
    provider: example
    hostname: example.com
    api-endpoint: https://example.com/api/v3
    repo: dependabot/smoke-tests
```

### Assertions used

Typically only a handful of available assertions are used:
- `stdout` asserts that text appeared on a line in stdout from the last `dependabot` command
- `stderr` is the same as `stdout` except it looks at stderr
- `pr-created` asserts that one of the created PRs matches the file that's given
- `pr-updated` is the same as `pr-created` but only looks at the updated PRs

Additionally, you can add a `!` before the command, like `! pr-created` to assert that the command will fail. This includes the `dependabot` command!

## Executing the tests

You will need Docker and the Dependabot CLI installed and on your path.

To execute all the tests, run `script/updater-e2e`. For a specific test, specify a part of the name as an argument, like `script/updater-e2e group`.

