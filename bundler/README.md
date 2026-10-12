## `dependabot-bundler`

Ruby (bundler) support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell bundler
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd bundler && rspec
   ```

### Native helper Bundler runtime

The native helper at `helpers/v2` runs under Bundler 4 by default. Two
environment variables can override the Bundler version installed by `build`
and activated by `run.rb`, which is intended for staged rollouts and
emergency rollback to Bundler 2:

- `DEPENDABOT_BUNDLER_VERSION_CONSTRAINT` (preferred)
- `BUNDLER_VERSION_CONSTRAINT` (fallback)

Both accept any RubyGems requirement string, e.g. `~> 4.0`, `~> 2.7`, or a
comma-separated list like `>= 2.4, < 5`. When neither is set the helper uses
`~> 4.0` for installation and `>= 2.4, < 5` for activation.

[core-repo]: https://github.com/dependabot/dependabot-core
