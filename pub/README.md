## `dependabot-pub`

Pub/Dart (including Flutter) support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers
   ```
   $ helpers/build helpers/install-dir/pub
   ```

2. Install Ruby dependencies
   ```
   $ pub install
   ```

3. Run tests
   ```
   $ bundle exec rspec spec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
