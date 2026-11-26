# Manifest-set catalog

`catalog.json` is a static, data-only description of which files in a directory make up a
*manifest set* for an ecosystem, and which package manager owns that set. It is shipped as data so
that downstream dependency-graph consumers can apply exactly the same rules as Dependabot Core
without re-implementing ecosystem logic. `Dependabot::ManifestSets.catalog` loads and validates it.

| File | Purpose |
| --- | --- |
| `catalog.json` | The catalog (schema version 1). |
| `catalog.schema.json` | JSON Schema (2020-12) for the document shape. |
| `fixtures/filenames.json` | Basename → expected matching rule IDs. A case may carry its own `catalog` (a JSON string). |
| `fixtures/owners.json` | Directory basenames → expected owner, or `"ambiguous": true`. A case may carry its own `catalog` (a JSON string) instead of using `catalog.json`. |
| `fixtures/invalid_catalogs.json` | Catalogs that must be rejected, with the expected error code. |
| `digests.json` | sha256 of every published file, for vendoring (see below). |

## Format

```json
{
  "schema_version": 1,
  "ecosystems": [
    {
      "id": "pypi",
      "inputs_matched_by_rules": false,
      "path_rules": [{ "id": "python-project", "filename_regex": "\\A(?:pyproject\\.toml)\\z", "directory": "parent" }],
      "owners": [{ "id": "uv", "when_any_basename": ["uv.lock"] }, { "id": "pip", "otherwise": true }]
    }
  ]
}
```

- `schema_version` must be the JSON integer `1`.
- Identifiers match `\A[a-z0-9][a-z0-9_.-]{0,63}\z` and are unique within their list.
- A path rule matches an entire **basename** (never a path). Its set directory is the directory
  containing the file (`"directory": "parent"` is the only v1 value). Several matching rules in one
  directory describe the same set.
- A directory holds a set when any file directly in it matches any path rule of the ecosystem. When
  none does (including when the directory no longer exists), the set is absent.
- Presence owners (`when_any_basename`) are evaluated before the `"otherwise": true` owner. If
  exactly one presence owner has a basename present in the directory it owns the set; if more than
  one does, ownership is **ambiguous** and the set is unresolvable (it is never first-match-wins).
  If none does, the `otherwise` owner applies. At most one owner may be `otherwise`, and it must be
  last; without one, a directory matching no selector has no owner.
- Owner IDs are package-manager names and are unique across the whole catalog, so a job's package
  manager identifies its ecosystem.
- `inputs_matched_by_rules: true` promises that every file a set can report as an input matches one
  of the ecosystem's rules. It is `false` for pypi because lockfiles such as `Pipfile.lock`, and
  files referenced with `-r`/`-c`, are inputs without defining a set.

Unknown fields, duplicate object keys, comments, invalid UTF-8, unpaired UTF-16 surrogate escapes
(such as `"\ud800"`) or anything that is not strict RFC 8259 JSON reject the **whole** catalog;
nothing is partially loaded.

## Portable regex subset

`filename_regex` must behave identically in Ruby's Onigmo and Go's RE2, so only this subset is
accepted:

- starts with `\A` and ends with `\z`, with no top-level `|`;
- groups `(...)` and `(?:...)` only (no flags, lookaround or backreferences). Inline flags such
  as `(?i:` are excluded because both engines apply Unicode case folding under them (U+212A
  KELVIN SIGN matches `k`, U+017F LATIN SMALL LETTER LONG S matches `s`) and their folding tables
  are not guaranteed to agree. Case-insensitivity is written out as ASCII classes such as
  `[Rr][Ee]`, so it never matches non-ASCII characters;
- escapes: `\t \n \v \f \r` and the punctuation `` . ^ $ | ? * + ( ) [ ] { } \ / - ``;
- character classes without nesting, POSIX classes, `&&`, or a leading `]`;
- quantifiers `* + ?` and `{n}`, `{n,}`, `{n,m}` (n ≤ m ≤ 1000, no leading zeros, since Go reads
  `{01}` as literal text); no lazy or possessive forms. Counts of nested `{n,m}` repetitions may
  not multiply past 1000 (Go's limit), counting `{n,}` as n and ignoring anything under `{0}`;
- no `^`/`$` anchors (Ruby treats them as line anchors).

## Limits and error codes

The catalog must be at most 1 MiB, contain at most 4096 rules, nest at most 32 levels deep, and
each regex must be at most 1024 bytes. Validation failures raise
`Dependabot::ManifestSets::InvalidCatalog` with one of these `code`s: `invalid_json`,
`duplicate_key`, `unknown_field`, `unsupported_schema_version`, `missing_field`, `invalid_type`,
`invalid_identifier`, `duplicate_ecosystem_id`, `duplicate_rule_id`, `duplicate_owner_id`,
`invalid_owner_order`, `invalid_directory`, `missing_anchor`, `non_portable_regex`,
`regex_too_long`, `invalid_regex`, `too_many_rules`, `catalog_too_large`.

## Keeping the rules honest

- `common/spec/dependabot/manifest_sets/catalog_spec.rb` runs every fixture through the Ruby
  validator and checks the schema and validator agree on fields.
- `go_modules/helpers/manifestsetparity` is a reference Go reader (RE2). Its tests run the same
  fixtures, so the two regex engines must agree on every case. Run it with
  `cd go_modules/helpers && go test ./manifestsetparity`; it is part of `go_modules/script/ci-test`.
- `python/spec/dependabot/python/file_fetcher_manifest_set_catalog_spec.rb`,
  `uv/spec/dependabot/uv/file_fetcher_manifest_set_catalog_spec.rb` and
  `go_modules/spec/dependabot/go_modules/file_fetcher_manifest_set_catalog_spec.rb` check the rules against
  what the fetchers and graphers actually accept, so a change there fails until the catalog follows.

## Ecosystem notes

**pypi.** The `.txt` rules mirror the requirements grapher's name filters, applied to basenames;
only the keyword is case-insensitive, and only for ASCII letters (the grapher's filters also fold
U+017F LONG S to `s`; the catalog deliberately does not), because the fetcher's `.txt` extension check is
case-sensitive. `.in` files match by name only (Core additionally checks their content). A
directory holding only `uv.lock` still holds a set, although the uv fetcher needs `pyproject.toml`
next to it.

Known v1 limitation: Core treats `requirements/*.txt` in a subdirectory as part of the parent
directory's job, whereas catalog rules only look at files directly in a directory. Jobs whose inputs
are not described by the catalog report the set as unresolvable (`unknown_provenance`) rather than
guessing.

**golang.** Only `go.mod` defines a set. `go.sum`, `go.env` and `go.work.sum` are not inputs, and
`go.work` workspaces are reported as unresolvable.

## Vendoring

Consumers should vendor the published files from a pinned Dependabot Core commit rather than
tracking a branch. `digests.json` lists every published file (the catalog, its schema and the
fixtures, by path relative to this directory and sorted by bytes) with its sha256:

```json
{ "schema_version": 1, "algorithm": "sha256", "files": [{ "path": "catalog.json", "sha256": "…" }] }
```

After copying, hash each listed file and compare. A consumer should refuse a copy where any hash
differs or a listed file is missing. `TestDigestManifest` in
`go_modules/helpers/manifestsetparity` is a reference implementation of that check. Run the
fixtures through the consumer's own reader as well; that is what keeps independent readers in step
with the validator.

`bin/update-manifest-set-digests.rb` regenerates the manifest after any published file changes.
`--check` reports whether it is stale, and `common/spec/dependabot/manifest_sets/digests_spec.rb`
fails CI until it is regenerated.

## Graph versions

Each owner's submissions carry an opaque, non-empty `graph_version`. A consumer may reuse a graph
only while both the set's inputs and that version are unchanged, so the version must change
whenever the grapher could produce different output for the same inputs. The catalog deliberately
carries no graph version.

`common/lib/dependabot/dependency_graphers/graph_versions.json` locks every catalog owner's version
to a sha256 of the sources that shape its graph (the shared base grapher, the owner's grapher and
the parsing it relies on, including native parser helpers). Each ecosystem's grapher spec fails once those sources change and the lock
has not been refreshed. Refresh it with an explicit decision per changed owner:

- `bin/update-manifest-set-graph-versions.rb --bump OWNER` when the output can change.
- `bin/update-manifest-set-graph-versions.rb --keep OWNER` when it cannot, for example a pure refactor.

`--check` reports owners whose lock is stale. When a grapher starts depending on another file, add it to
that owner's `sources`; if the file lives in another ecosystem's directory, also check that owner in that
ecosystem's grapher spec so the guard runs when only that file changes (the Python spec checks uv).

## Snapshot metadata

With the `emit_manifest_set_envelope` experiment enabled (it is off by default), a job whose package
manager is a catalog owner adds one snapshot metadata entry, `manifest_set`. Its value is a JSON
**string** so that the metadata map stays string-to-string:

```json
{
  "schema_version": 1, "ecosystem": "pypi", "directory": "api", "owner": "pip", "graph_version": "1",
  "state": "present",
  "files": [{ "path": "api/requirements.txt", "blob_oid": "2222222222222222222222222222222222222222" }]
}
```

- `directory` is the job directory in canonical form: `/api/` becomes `api` and `/` becomes `.`. It
  always names the same directory as the snapshot's `scanned_manifest_path`.
- `present` lists every original repository input (path and Git blob OID), including selector files
  for other owners in the directory, sorted by path. An empty dependency graph can still be present.
- `absent` carries `"files": []`. It is reported when the job finds no manifests, which includes a
  directory that was deleted. Its `owner` and `graph_version` are only there for schema uniformity.
- `unresolvable` carries a `reason` and no `files`: `input_limit` (more than 4096 files, a path over
  4096 bytes or an envelope over 1 MiB; lists are never truncated), `workspace` (a `go.work` in the
  directory), `local_replace` (a Go `replace` pointing inside the repository), `ambiguous_owner` or
  `unknown_provenance`.
- Failed, degraded and error-skipped snapshots, and jobs whose package manager is not an owner,
  carry no `manifest_set`.

The snapshot metadata map allows at most eight entries, including keys added after submission;
`GithubApi::DependencySubmission` refuses to build metadata over that budget.

## Changing the catalog

Bumping the meaning of an existing rule invalidates every set it describes downstream, so prefer
adding rules. Update the fixtures alongside any rule change; each rule needs at least one positive
and one negative fixture. Then run `bin/update-manifest-set-digests.rb`.
