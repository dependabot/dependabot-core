## `dependabot-uv`

Python `uv` support for [`dependabot-core`][core-repo].

### Updating supported Python version

We rely on `pyenv` to manage Python's versions.

Updating the list of known versions might be tricky, here are the steps:

1. Update the `pyenv` version in the [`Dockerfile`](https://github.com/dependabot/dependabot-core/blob/main/uv/Dockerfile), you may use a commit hash if a new `pyenv` version is not released yet.
2. Update the `pyenv global` version in the `Dockerfile`. We always use the latest (and greatest) Python version.
3. Update the list of known Python versions in [`language.rb`](https://github.com/dependabot/dependabot-core/blob/main/python/lib/dependabot/python/language.rb) (`PRE_INSTALLED_PYTHON_VERSIONS_RAW`). `uv/lib/dependabot/uv/language.rb` aliases it, so there is nothing to change on the uv side.
4. Fix any broken tests.

[Example PR](https://github.com/dependabot/dependabot-core/pull/13321) that does all these things

### Running locally

1. Start a development shell

  ```shell
  $ bin/docker-dev-shell uv
  ```

2. Run tests

   ```shell
   [dependabot-core-dev] ~ $ cd uv && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

