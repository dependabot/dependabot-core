## `dependabot-cargo`

Rust (Cargo) support for [`dependabot-core`][core-repo].

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell cargo
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd cargo && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core

### Offline lock graph helper (spike)

`helpers/` builds a standalone Rust binary using RustSec's public `cargo-lock`
crate. It reads stdin and writes stdout; it never invokes Cargo, reads a project,
or accesses the network at runtime. Build/install it inside the Cargo development
container with `bash helpers/build`. The updater image installs it at
`$DEPENDABOT_NATIVE_HELPERS_PATH/cargo/bin/lock-graph`; local builds default to
`helpers/install-dir/cargo/bin/lock-graph`.

The existing native-helper protocol accepts named snapshots in one process:

```json
{"function":"lock_graph","args":[[{"name":"before","content":"<Cargo.lock contents>"},{"name":"after","content":"<Cargo.lock contents>"}]]}
```

Ruby callers explicitly require `dependabot/cargo/lockfile_graph` and call
`Dependabot::Cargo::LockfileGraph.facts(snapshots: { "before" => lockfile })`,
where each value is a `Dependabot::DependencyFile`. No updater call site uses it.

The response is `{"result":{"schema_version":1,"snapshots":[...]}}`.
Each snapshot has `name`, `lockfile_version` (detected V1/V2 or explicit V3/V4),
`complete`, `packages`, `edges`, and `diagnostics`. Package identities are
`{"name":"...","version":"...","source":"..."}`; versions are normalized semver
strings, **not compared**, and source strings retain their original TOML-decoded
spelling, including Git selectors and commit fragments. A null source means the
lockfile supplies no source (typically a workspace/path package); it does not
identify a filesystem path.

Edges contain `from` and `to` package identities and `kind` (`dependency` or
`replacement`). Compact references resolve only when exactly one package matches
the supplied name/version/source. Source-qualified Git references may omit the
commit fragment, but must match the URL and selector. Ambiguous or missing targets
never produce guessed edges. Duplicate package entries likewise make the graph
incomplete. Packages, edges, diagnostics, and snapshots are sorted deterministically
(identity ordering is lexical, not version precedence).

Diagnostics have `code`, `message`, nullable `package` and `reference`, and
`candidates`. Invalid lockfiles produce an incomplete snapshot with `parse_error`,
a null lockfile version, and no graph; other snapshots still parse. Invalid
protocol input exits nonzero with the standard helper error envelope.

`complete` means every represented lockfile reference resolves uniquely, not that
the graph captures build-time features, target conditions, dependency kinds,
workspace membership, or manifest declarations. Legacy `[root]` is included;
`patch.unused`, metadata, and checksums are not graph facts. Unsupported future
formats fail parsing. Conservative Git selector matching can mark unusual
abbreviated-revision references incomplete rather than conflate identities.
This helper makes no update-acceptance or security decisions.

Inside the Cargo development container, run `cargo test --locked`,
`cargo fmt -- --check`, and `cargo clippy --locked --all-targets -- -D warnings`
from `cargo/helpers/`. Rust integration tests execute the binary with an empty
`PATH`; they require no Cargo installation or network access at runtime.
