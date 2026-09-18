# Ecosystem Families

Many of Dependabot's ecosystems are **not fully independent** — several are different tools for the **same language**, so they often target the same dependencies and registries and *may* share logic (dependency resolution, version comparison, requirement parsing), even if each keeps its own manifest/build-file handling.

Because of that, a bug or improvement is often — **but not always** — general to the whole family rather than specific to the one ecosystem where it was reported. Treat the family as a **prompt to check the siblings**, not a guarantee that they share code or need the same change.

> [!IMPORTANT]
> When you investigate or change one ecosystem, **consider its siblings in the same family**. If the root cause *could* be general (dependency resolution, registry handling, version comparison, requirement parsing, error handling, etc.), check whether the siblings have the same issue — they might share code, duplicate the logic, or diverge entirely. Verify in the code, and update the ones that are actually affected, each with its own tests.

## The families

| Family | Ecosystems |
| --- | --- |
| **JavaScript / TypeScript** | `npm_and_yarn` (npm, Yarn, pnpm), `bun`, `deno`, `nub` |
| **Python** | `python` (pip, pip-compile, pipenv, Poetry), `uv`, `conda` |
| **JVM** | `maven`, `gradle`, `sbt` |
| **Containers** | `docker`, `docker_compose` |

Grouping is a **heuristic for what to check**, not a statement of code sharing. How much siblings actually share in code varies — from heavy reuse to near-independent reimplementations — so confirm the real relationship before assuming a fix carries over.

Single-tool ecosystems (e.g. `bundler`, `cargo`, `go_modules`, `hex`, `nuget`, `pub`, `composer`, `elm`, `swift`, `github_actions`, `git_submodules`) have no sibling to mirror, but changes in `common/` still affect every ecosystem.

## How the change might reach siblings

Grouping is a **prompt to check**, not a guarantee that siblings share code. When a fix is general, verify how (or whether) each sibling is affected. In practice a sibling tends to fall into one of two patterns:

- **Possibly shared in code** — a sibling may reuse another's classes (for example, the JVM tools may lean on `maven`; `uv`/`conda` may lean on `python`; `docker_compose` may lean on `docker`). Where that's the case the fix can reach them at runtime, but you should still run **their** test suites to confirm.
- **Possibly duplicated / independent** — a sibling may reimplement the same behavior separately (for example, `bun` and `npm_and_yarn`), or be largely its own implementation (`deno`). Where logic is duplicated, fix every affected sibling. **Prefer consolidating shared behavior into a common base** when practical, so the fix lives in one place; otherwise fix each duplicate — but don't introduce *new* duplication just to match a sibling.

Confirm the actual relationship in the code before assuming either. If a sibling intentionally differs, note why in the code/PR instead of forcing parity.

## Workflow

1. Identify the ecosystem and the class involved.
2. Decide whether the root cause is **ecosystem-specific** or **could be general to the family**.
3. If it might be general, check each sibling in the code and fix the ones that are actually affected. Prefer sharing the logic through a common base when practical; otherwise fix each duplicate. Add tests either way.
4. Validate each affected ecosystem's test suite, not just the one you started from.
