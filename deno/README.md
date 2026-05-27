## `dependabot-deno`

Deno support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell deno
  ```

2. Run tests
  ```
  [dependabot-core-dev] ~ $ cd deno && rspec
  ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Implementation Status

#### Required Classes
- [x] FileFetcher
- [x] FileParser
- [x] UpdateChecker
- [x] FileUpdater (manifest + `deno.lock` regeneration)

#### Optional Classes
- [x] MetadataFinder (npm sources; jsr returns nil)
- [x] Version
- [x] Requirement

#### Supporting Infrastructure
- [x] Comprehensive unit tests
- [x] CI/CD integration
- [x] Documentation

### Supported

- `deno.json` and `deno.jsonc` import maps
- `jsr:` and `npm:` specifiers (scoped, unscoped, versionless, sub-path)
- `deno.lock` regeneration when the manifest changes
- Cooldown for direct dependencies

### Not yet supported (planned)

- HTTPS imports (`https://deno.land/x/...`)
- `scopes` field overrides
- `vendor/` directory regeneration
- Workspaces (nested `deno.json`)
- `links` field (local package overrides)
- `DENO_AUTH_TOKENS` / private registries
- Frozen-lockfile UX (we pass `--frozen=false` and may overwrite a frozen lockfile)
- Custom lockfile path (`"lock": { "path": "..." }`)
