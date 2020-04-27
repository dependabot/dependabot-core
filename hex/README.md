## `dependabot-hex`

Elixir support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers
   ```
   $ helpers/build helpers/install-dir/hex
   ```

2. Install Ruby dependencies
   ```
   $ bundle install
   ```

3. Run tests
   ```
   $ export DEPENDABOT_NATIVE_HELPERS_PATH=$PWD/helpers/install-dir
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
