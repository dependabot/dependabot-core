# Manifest-set catalog

`catalog.json` is a static, data-only description of which files in a directory make up a
*manifest set* for an ecosystem, and which package manager owns that set. It is shipped as data so
that downstream dependency-graph consumers can apply exactly the same rules as Dependabot Core
without re-implementing ecosystem logic. `Dependabot::ManifestSets.catalog` loads and validates it.

| File | Purpose |
| --- | --- |
| `catalog.json` | The catalog (schema version 1). |
| `catalog.schema.json` | JSON Schema (2020-12) for the document shape. |
| `fixtures/filenames.json` | Basename → expected matching rule IDs. |
| `fixtures/owners.json` | Directory basenames → expected owner. |
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
- Owners are evaluated in order: the first owner with a `when_any_basename` entry present in the
  directory wins, otherwise the `"otherwise": true` owner does. At most one owner may be
  `otherwise`, and it must be last; without one, a directory matching no selector has no owner.
- `inputs_matched_by_rules: true` promises that every file a set can report as an input matches one
  of the ecosystem's rules. It is `false` for pypi because lockfiles such as `Pipfile.lock`, and
  files referenced with `-r`/`-c`, are inputs without defining a set.

Unknown fields, duplicate object keys, comments, invalid UTF-8 or anything that is not strict
RFC 8259 JSON reject the **whole** catalog; nothing is partially loaded.

## Portable regex subset

`filename_regex` must behave identically in Ruby's Onigmo and Go's RE2, so only this subset is
accepted:

- starts with `\A` and ends with `\z`, with no top-level `|`;
- groups `(...)`, `(?:...)` and `(?i:...)` only (no other flags, lookaround or backreferences);
  `(?i:` is allowed only in ASCII-only patterns;
- escapes: `\t \n \v \f \r` and the punctuation `` . ^ $ | ? * + ( ) [ ] { } \ / - ``;
- character classes without nesting, POSIX classes, `&&`, or a leading `]`;
- quantifiers `* + ?` and `{n}`, `{n,}`, `{n,m}` (n ≤ m ≤ 1000); no lazy or possessive forms;
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
only the keyword is case-insensitive, because the fetcher's `.txt` extension check is
case-sensitive. `.in` files match by name only (Core additionally checks their content). A
directory holding only `uv.lock` still holds a set, although the uv fetcher needs `pyproject.toml`
next to it.

Known v1 limitation: Core treats `requirements/*.txt` in a subdirectory as part of the parent
directory's job, whereas catalog rules only look at files directly in a directory. Jobs whose inputs
are not described by the catalog report the set as unresolvable rather than guessing.

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

## Changing the catalog

Bumping the meaning of an existing rule invalidates every set it describes downstream, so prefer
adding rules. Update the fixtures alongside any rule change; each rule needs at least one positive
and one negative fixture. Then run `bin/update-manifest-set-digests.rb`.
