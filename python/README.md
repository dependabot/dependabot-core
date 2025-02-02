## `dependabot-python`

Python support for [`dependabot-core`][core-repo].

### Updating supported Python version

We rely on `pyenv` to manage Python's versions.

Updating the list of known versions might be tricky, here are the steps:

1. Update the `pyenv` version in the [`Dockerfile`](https://github.com/dependabot/dependabot-core/blob/main/python/Dockerfile), you may use a commit hash if a new `pyenv` version is not released yet.
2. Update the `pyenv global` version in the `Dockerfile`. We always use the latest (and greatest) Python version.
3. Update the list of known Python versions in [`language_version_manager.rb`](https://github.com/dependabot/dependabot-core/blob/main/python/lib/dependabot/python/language_version_manager.rb).
4. Fix any broken tests.

[Example PR](https://github.com/dependabot/dependabot-core/pull/8732) that does all these things.

### Running locally

1. Start a development shell

  ```shell
  $ bin/docker-dev-shell python
  ```

2. Run tests

   ```shell
   [dependabot-core-dev] ~ $ cd python && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
