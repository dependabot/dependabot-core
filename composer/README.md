## `dependabot-composer`

PHP (Composer) support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers
   ```
   $ export DEPENDABOT_NATIVE_HELPERS_PATH=$PWD/helpers/install-dir
   $ helpers/v1/build
   $ helpers/v2/build
   ```

   Note: We expect Composer v1 to be available as `composer`, you can skip `helpers/v1/build` if you are working on the
   latest version, but some test may fail.

2. Install Ruby dependencies
   ```
   $ bundle install
   ```

3. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
