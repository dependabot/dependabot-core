## `dependabot-bundler`

Ruby (bundler) support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers
    ```
    $ export DEPENDABOT_NATIVE_HELPERS_PATH=$PWD/helpers/install-dir
    $ helpers/v1/build
    $ helpers/v2/build
    ```

2. Install Ruby dependencies
   ```
   $ bundle install
   ```

2. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
