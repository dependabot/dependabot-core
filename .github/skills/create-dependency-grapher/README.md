# Create Dependency Grapher

A Copilot agent skill for this repository that guides you through adding a `DependencyGrapher`
to a Dependabot ecosystem gem.

## What it does

`Dependabot::DependencyGraphers` convert an ecosystem's parsed dependencies into the graph
structure GitHub's [Dependency Submission API](https://docs.github.com/en/rest/dependency-graph/dependency-submission)
expects. Not every ecosystem gem in this repo has one yet.

This skill runs an interactive, iterative build for a new grapher:

1. Investigates the target ecosystem's `FileParser` and gathers requirements (PURL type,
   whether ephemeral lockfile generation is needed, whether the ecosystem needs manifest
   grouping/"layering" for directories that hold multiple independent manifests).
2. Scaffolds the basic `DependencyGrapher` class and its spec.
3. Iterates — subdependency fetching, then (if needed) manifest grouping, then (if needed)
   ephemeral lockfile generation — with a code review checkpoint (tests, lint, Sorbet) after
   each stage.

See `SKILL.md` for the full step-by-step instructions the agent follows, and
`references/manifest-layering.md` / `references/ephemeral-lockfiles.md` for the detailed
procedures for those two optional features.

## When to use it

Use this skill when you need to:

- Add dependency graph support to an ecosystem gem that doesn't have it yet.
- Understand the `DependencyGrapher` pattern before implementing one yourself.
- Work out whether a specific ecosystem needs ephemeral lockfile generation or manifest
  grouping (layering).

It is **not** the right tool for changing a `FileParser` — dependency graphers are built to
never alter the parser layer (see the Boundaries section of `SKILL.md`).

## How to use it

This is a project skill, so it's automatically available to Copilot CLI when working in this
repository (`.github/skills/create-dependency-grapher/`). Just ask, for example:

```
I need to add a DependencyGrapher to the Cargo ecosystem.
```

or invoke it explicitly:

```
Use the /create-dependency-grapher skill to add a DependencyGrapher for Composer.
```

## A note on portability

Unlike most agent skills, this one is intentionally **not** self-contained in the portable
sense — its instructions reference files throughout the repository (e.g.
`{ecosystem}/lib/dependabot/{ecosystem}/dependency_grapher.rb`,
`common/lib/dependabot/dependency_graphers/README.md`).

That's a deliberate choice: this skill
only makes sense running inside a checkout of `dependabot-core`, and isn't meant to be copied
into another repository's skills directory. Only the two `references/*.md` files (the layering
and ephemeral-lockfile procedures) are self-contained within the skill root.
