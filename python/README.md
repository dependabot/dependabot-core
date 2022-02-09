## `dependabot-python`

Python support for [`dependabot-core`][core-repo].

### Updating supported Python version

We rely on `pyenv` to manage Python's versions.

Updating the list of known versions might be tricky, here are the steps:
1. Update `pyenv` version in our [`Dockerfile`](https://github.com/dependabot/dependabot-core/blob/main/Dockerfile), you may use commit hash if new `pyenv` version is not released yet
2. Then, update `pyenv global` version in `Dockerfile`, we always use the latest (and the greatest) Python version there is
3. The next step is to update our [`build`](https://github.com/dependabot/dependabot-core/blob/main/python/helpers/build) script, bump the latest Python version there
4. Now, update the list of known Python version in [`python_versions.rb`](https://github.com/dependabot/dependabot-core/blob/main/python/lib/dependabot/python/python_versions.rb)
5. The last step is to tweak our tests, if required. The easiest way to determine which one to tweak is just by analyzing the failing output

[Example PR](https://github.com/dependabot/dependabot-core/pull/3440) that does all these things.

### Running locally

1. Install native helpers
   ```
   $ export DEPENDABOT_NATIVE_HELPERS_PATH=$PWD/helpers/install-dir
   $ helpers/build
   ```

2. Install Ruby dependencies
   ```
   $ bundle install
   ```

3. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
