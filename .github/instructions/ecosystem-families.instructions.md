---
applyTo: "*/lib/dependabot/**,*/helpers/**,updater/**"
---

# Cross-Ecosystem Fix Propagation

Many ecosystems are different tools for the **same language**, so they often target the same dependencies and registries and *may* share logic — a bug or improvement is therefore often, **but not always**, general to the whole family, whether the logic is shared in code or duplicated.

**When you change one ecosystem, consider its siblings.** If the root cause could be general, check whether they have the same issue and update the ones that are actually affected — each with its own tests.

## Families

Grouping is a **prompt to check the siblings**, not a guarantee they share code. How much they share varies — from heavy reuse to near-independent reimplementations — so confirm the real relationship in the code.

- **JavaScript / TypeScript**: `npm_and_yarn` (npm, Yarn, pnpm), `bun`, `deno`
- **Python**: `python` (pip, pip-compile, pipenv, Poetry), `uv`, `conda`
- **JVM**: `maven`, `gradle`, `sbt`
- **Containers**: `docker`, `docker_compose`

A change to `common/` affects **every** ecosystem.

## How the fix might reach siblings

- **Possibly shared in code** — a sibling may reuse another's classes (for example, the JVM tools may lean on `maven`; `uv`/`conda` may lean on `python`; `docker_compose` may lean on `docker`). Where that's the case the fix reaches them at runtime, but still run **their** test suites.
- **Possibly duplicated / independent** — a sibling may reimplement the same behavior (for example, `bun` and `npm_and_yarn`), or be largely its own implementation (`deno`). Where logic is duplicated, fix every affected sibling. Prefer consolidating shared behavior into a common base when practical; otherwise fix each duplicate. Don't introduce new duplication just to match a sibling.

Confirm the actual relationship before assuming a fix carries over. If a sibling intentionally differs, note why in the code/PR instead of forcing parity.

See [`ECOSYSTEM_FAMILIES.md`](../../ECOSYSTEM_FAMILIES.md) for the full map and workflow.
