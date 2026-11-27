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

### Ruby graph-transition policy (spike, layer 2)

Explicitly require `dependabot/cargo/graph_transition_policy`. Layer 3 below is
the only production caller. It consumes the helper's schema-v1 facts without
parsing lockfile text or invoking Cargo metadata:

```ruby
policy = Dependabot::Cargo::GraphTransitionPolicy
previous = policy::Package.new(
  name: dependency.name,
  version: dependency.previous_version,
  source: "registry+https://github.com/rust-lang/crates.io-index"
)
intent = policy::Intent.from_dependency(dependency: dependency, previous: previous)
result = policy.evaluate(facts: facts, intents: [intent], before: "before", after: "after")
result.status.serialize # "accepted", "rejected", or "unknown"
result.reasons.map(&:serialize)
```

The caller must resolve the exact previous name/version/source from helper facts,
not guess a registry or collapse duplicate sources. `Intent.from_dependency`
checks the supplied identity against Dependabot's name/previous version and
retains its source. Construct `Intent.new(previous:, target:, parents:)` directly
for an explicit subset of incoming parents; omitted `parents` selects all incoming
edges. This supports split updates where the old package remains for other
parents. Source-changing updates (including changed Git commit fragments) are
unknown, not compared across origins.

Acceptance proves a **lockfile-level** edge property, not manifest compatibility:
each selected old edge disappears and its correlated parent has an edge of the
same kind to the exact target. An already-present target is sufficient, including
`{1,2,3}->{1,3}` and several incoming edges. Parent updates correlate through exact
group intents only when the old parent disappears and the target parent exists.
Retained old/new parent pairs are ambiguous. Replacement and dependency edges
are checked separately. Unselected incoming edges and other pre-existing
same-name/same-source destinations must remain unchanged.

Ruby's Cargo version class rejects proven edge downgrades and requested
downgrades. All other unproven transitions are unknown: unchanged selected edges,
missing or ambiguous destinations, newly introduced competing destinations,
uncorrelated parents, root packages without incoming edges, invalid selections,
conflicting intents, incomplete/ambiguous helper facts, and unsupported schemas.
When Cargo selects another higher version, the observed identity is retained in
an `alternative_version` reason; lockfile facts cannot prove its manifest
requirements or advisory/ignore-policy compatibility. The caller must decide how
to handle unknown results; this spike deliberately does not invent a fallback.

Each reason has a status, code, message, and optional snapshot, previous package,
old parent, and observed destination. Helper diagnostics retain their code,
message, snapshot, and package, plus the full diagnostic (including reference
and candidate identities). Rejected reasons dominate unknown reasons, which
dominate accepted reasons within a fully validated graph. Incomplete input facts
stop evaluation with unknown before transition checks. Acceptance does not audit
unrelated packages, newly introduced parents, feature/target conditions, or
manifest declarations; graph deduplication cannot prove which declaration was
rewritten when a parent already referenced both versions.

Inside the Cargo development container:

```bash
cd /home/dependabot/cargo
bundle exec rspec spec/dependabot/cargo/graph_transition_policy_spec.rb spec/dependabot/cargo/lockfile_graph_spec.rb
bundle exec rubocop lib/dependabot/cargo/graph_transition_policy.rb spec/dependabot/cargo/graph_transition_policy_spec.rb
```

### Lockfile updater integration (spike, layer 3)

`FileUpdater::LockfileUpdater` validates every non-Git update with exact numeric
previous and target versions through `FileUpdater::GraphUpdateValidator`. After
Cargo runs, the validator sends the original and final `Cargo.lock` to the helper
in a single call. Then it resolves each previous identity from the
`cargo_package_source` metadata or a unique registry package in the original
facts. Finally, it evaluates all of the update's intents together so grouped
parent updates correlate.

The policy is evaluated with unscoped intents first, so every incoming edge must
move. If the result is unknown, it is evaluated once more with direct dependencies
scoped to the workspace packages whose manifests declare them. This accepts split
graphs where other consumers keep the previous version. Dependencies declared in
`[workspace.dependencies]` stay unscoped. Only `accepted` succeeds. `rejected`,
`unknown`, incomplete facts, unresolved identities, and helper failures log a
`Cargo lock graph validation <status>: <reason codes>` warning and raise
`Dependabot::UpdateNotPossible`.

Covered updates no longer use the textual target-present/version-set checks.
Git updates and updates without exact numeric versions keep the existing checks.
The plain/`--precise` command orchestration is unchanged.

```bash
bundle exec rspec spec/dependabot/cargo/file_updater/lockfile_updater_spec.rb
```
