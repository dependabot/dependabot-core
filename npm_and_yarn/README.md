## `dependabot-npm_and_yarn`

Yarn and npm support for [`dependabot-core`][core-repo].

### Running locally

1. Install native helpers

   ```
   $ cd helpers && yarn install && cd -
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
