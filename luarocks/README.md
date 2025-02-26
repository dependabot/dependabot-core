## `dependabot-luarocks`

Luarocks support for [`dependabot-core`][core-repo].

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
