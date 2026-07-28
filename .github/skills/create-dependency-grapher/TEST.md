# Behavioral Tests: create-dependency-grapher

## Test: Activates on a request to add a grapher to a new ecosystem

**Prompt:**
```
I need to add a DependencyGrapher to the Cargo ecosystem.
```

**Expected Behavior:**
Activates this skill. Starts by asking which ecosystem gem needs a `DependencyGrapher` (or
confirms Cargo if already stated), then investigates `cargo/lib/dependabot/cargo/file_parser.rb`
and its spec before asking any requirements questions. Does not start writing the grapher class
before gathering PURL type / ephemeral lockfile / layering requirements.

## Test: Does not activate on unrelated update-checker or file-fetcher work

**Prompt:**
```
The Bundler UpdateChecker is picking the wrong version for a pinned gem, can you fix it?
```

**Expected Behavior:**
Does NOT activate this skill — this is an `UpdateChecker` bug, unrelated to dependency graphing.

## Test: Only asks about ephemeral lockfiles when relevant

**Prompt:**
```
Add a DependencyGrapher to an ecosystem that always has a committed lockfile and never
resolves manifest-only projects.
```

**Expected Behavior:**
Does not ask "should we generate ephemeral lockfiles?" for that package manager, and does not
implement or scaffold a `LockfileGenerator` class or `prepare!` override for it. The Prepare for
Ephemeral Lockfile Generation / Implement Ephemeral Lockfile Generation steps are skipped
entirely, and `references/ephemeral-lockfiles.md` is not loaded.

## Test: Only asks about manifest grouping (layering) when relevant

**Prompt:**
```
Add a DependencyGrapher to an ecosystem where each directory only ever has exactly one
manifest + one lockfile.
```

**Expected Behavior:**
Does not ask about layering, does not override `manifest_groups`, and does not load
`references/manifest-layering.md`. The default `Dependabot::DependencyGraphers::Base` single-
group behavior is left untouched.

## Test: Asks about layering for an ecosystem with multiple independent manifests per directory

**Prompt:**
```
Add a DependencyGrapher to GitHub Actions. A .github/workflows/ directory can hold several
independent workflow files, each with its own action dependencies.
```

**Expected Behavior:**
During requirements gathering, confirms with the user that manifest grouping (layering) is
needed. Basic grapher class + tests are still built first, ignoring layering, before the
Implement Manifest Grouping step is reached. When that step is reached, reads and follows
`references/manifest-layering.md` (including its fall-back-to-`super` pattern) rather than
inventing a different approach, and points to
`python/lib/dependabot/python/dependency_grapher/requirements_layers.rb` as the reference
implementation.

## Test: Always runs the code review checklist before handing back

**Prompt:**
```
Continue implementing subdependency fetching for the grapher we started.
```

**Expected Behavior:**
Before asking the user to review the subdependency fetching work, runs (and fixes any failures
from) `bin/test {ecosystem} spec/dependabot/{ecosystem}`, `bin/lint -a` on the changed files, and
`bundle exec srb tc -a`. Does NOT skip straight to "please review" without running these.

## Test: Never proposes altering the FileParser

**Prompt:**
```
The grapher needs data the FileParser doesn't currently return — can you just add it to the
parser's return value?
```

**Expected Behavior:**
Declines to modify the `FileParser`. Instead proposes retrieving the missing information inside
the grapher itself (re-parsing a file, running a native command, etc.), citing the Boundaries
section of `SKILL.md`.
