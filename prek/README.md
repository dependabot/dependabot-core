## `dependabot-prek`

Dependabot support for [prek](https://prek.j178.dev/), a fast, drop-in alternative
to pre-commit. This gem keeps the remote hook repositories pinned in a project's
native `prek.toml` configuration up to date.

prek is configuration-compatible with pre-commit, so the version-resolution logic
is shared with the [`dependabot-pre_commit`](../pre_commit) gem; this gem adds the
`prek.toml` (TOML) file format on top of it.

### Running locally

1. Install Ruby dependencies

   ```
   $ bundle install
   ```

2. Run tests

   ```
   $ bundle exec rspec spec
   ```
