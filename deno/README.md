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

  The lockfile-regeneration specs (`spec/dependabot/deno/file_updater/lockfile_updater_spec.rb`) shell out
  to a real `deno install` and hit the JSR/npm registries. They expect the `deno` binary on `PATH` and
  network access — both are provided by the `bin/docker-dev-shell deno` image, but local runs outside
  the container need them too.

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

### Runtime

The updater image bundles a single Deno binary (`DENO_VERSION` in `deno/Dockerfile`).
It is kept current so it can read the latest `deno.lock` format; older lockfiles are
still read and are upgraded in place to the bundled Deno's format on regeneration.
Bumping `DENO_VERSION` may change the emitted `deno.lock` version — the
`lockfile_updater` specs pin the expected version so such bumps are intentional.

### Not yet supported (planned)

- HTTPS imports (`https://deno.land/x/...`)
- `scopes` field overrides
- `vendor/` directory regeneration
- Workspaces (nested `deno.json`)
- `links` field (local package overrides)
- `DENO_AUTH_TOKENS` / private registries
- Frozen-lockfile UX (we pass `--frozen=false` and may overwrite a frozen lockfile)
- Custom lockfile path (`"lock": { "path": "..." }`)
