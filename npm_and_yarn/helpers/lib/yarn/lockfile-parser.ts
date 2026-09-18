/* YARN.LOCK PARSER
 *
 * Inputs:
 *  - directory containing a yarn.lock
 *
 * Outputs:
 *  - JSON formatted yarn.lock
 */
import fs from "fs";
import path from "path";
import { LOCKFILE_ENTRY_REGEX } from "./helpers.js";
const parseLockfile =
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  require("@dependabot/yarn-lib/lib/lockfile/parse").default;

export interface LockfileEntry {
  version: string;
  resolved?: string;
  dependencies?: Record<string, string>;
}

// Yarn berry descriptors are prefixed with the protocol used to resolve them,
// e.g. `abind@npm:^1.0.0` or `my-app@workspace:.`. Only the `npm:` protocol
// resolves to a semver range we can reason about.
const NPM_PROTOCOL = "npm:";
const WORKSPACE_PROTOCOL = "workspace:";

// Yarn berry entries can list several descriptors for the same resolution,
// e.g. `"abind@npm:^1.0.0, abind@npm:^1.0.4"`.
const DESCRIPTOR_SEPARATOR = /\s*,\s*/;

const METADATA_KEY = "__metadata";

export async function parse(
  directory: string
): Promise<Record<string, LockfileEntry>> {
  const readFile = (fileName: string) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile(data).object;
}

// A single `name -> requirement` edge of the dependency graph. The original
// descriptor identity is preserved for lockfile lookups, while `realName`
// stores the de-aliased package name for vulnerability comparisons.
export interface DependencyEdge {
  name: string;
  requirement: string;
  realName?: string;
}

export interface NormalizedLockfileEntry extends DependencyEdge {
  version: string;
  resolved?: string;
  dependencies: DependencyEdge[];
}

// Parses a yarn.lock into a flat list of entries, one per descriptor, where the
// descriptors and the dependency edges are normalized in the same way so they
// can be compared against the requirements declared in a package.json manifest
// (also normalized, via `normalizeDescriptor`).
//
// Normalizing is required because yarn berry lockfiles, which are parsed by the
// yarn v1 parser too, keep the berry protocol prefixes and may group several
// descriptors under a single key. Yarn v1 lockfiles are normalized with the
// same rules, which only affects npm aliases (`alias@npm:real-pkg@^1.0.0`).
//
// A list is used rather than an object keyed by the normalized descriptor
// because distinct descriptors can normalize to the same edge while resolving
// to different versions, e.g. a manifest depending on both `foo@^1.0.0` and
// `foo-alias@npm:foo@^1.0.0`. Keying would discard one of the resolutions along
// with its dependency subtree.
export async function parseNormalized(
  directory: string
): Promise<NormalizedLockfileEntry[]> {
  return normalizeLockfile(await parse(directory));
}

// Resolves a `name`/`requirement` descriptor pair into a dependency edge.
// The alias name and original descriptor requirement are kept so lockfile entry
// lookup remains exact, but the de-aliased package name is stored separately for
// real-package comparisons (e.g. vulnerable dependency checks).
export function normalizeDescriptor(
  name: string,
  requirement: string
): DependencyEdge {
  if (requirement.startsWith(NPM_PROTOCOL)) {
    const rest = requirement.slice(NPM_PROTOCOL.length);
    const aliasMatch = rest.match(LOCKFILE_ENTRY_REGEX);
    if (aliasMatch && aliasMatch[2]) {
      return {
        name,
        requirement,
        realName: aliasMatch[1],
      };
    }
    return { name, requirement: rest };
  }

  return { name, requirement };
}

export function edgeKey(edge: DependencyEdge): string {
  return `${edge.name}@${edge.requirement}`;
}

// Finds every lockfile entry a dependency edge resolves to.
//
// Workspace ranges are matched by name alone: a `workspace:` range such as
// `workspace:*` or `workspace:^` is resolved by yarn to the workspace package
// of that name, whose lockfile descriptor carries the workspace's path
// (`local-pkg@workspace:packages/local-pkg`), so the two are never equal.
export function findEntries(
  lockfile: NormalizedLockfileEntry[],
  edge: DependencyEdge
): NormalizedLockfileEntry[] {
  if (isWorkspaceRequirement(edge.requirement)) {
    return lockfile.filter(
      (entry) =>
        entry.name === edge.name && isWorkspaceRequirement(entry.requirement)
    );
  }

  return lockfile.filter(
    (entry) =>
      entry.name === edge.name && entry.requirement === edge.requirement
  );
}

function isWorkspaceRequirement(requirement: string): boolean {
  return requirement.startsWith(WORKSPACE_PROTOCOL);
}

function normalizeLockfile(
  lockfileJson: Record<string, LockfileEntry>
): NormalizedLockfileEntry[] {
  const normalized: NormalizedLockfileEntry[] = [];

  for (const [entry, pkg] of Object.entries(lockfileJson)) {
    if (entry === METADATA_KEY) continue;

    const dependencies = normalizeDependencies(pkg.dependencies);

    for (const descriptor of entry.split(DESCRIPTOR_SEPARATOR)) {
      const match = descriptor.match(LOCKFILE_ENTRY_REGEX);
      if (!match) continue;

      const edge = normalizeDescriptor(match[1], match[2]);
      // Give each descriptor its own entry object and dependency list so that
      // callers mutating one entry don't affect the other descriptors sharing
      // this resolution. The edges themselves are treated as immutable values
      // and are intentionally shared.
      normalized.push({
        name: edge.name,
        requirement: edge.requirement,
        ...(edge.realName && { realName: edge.realName }),
        version: pkg.version,
        resolved: pkg.resolved,
        dependencies: [...dependencies],
      });
    }
  }

  return normalized;
}

// Dependencies are returned as a list rather than an object keyed by name so
// that aliased edges resolving to the same package (e.g. `foo: npm:^1.0.0` and
// `foo-v2: npm:foo@^2.0.0`) are all preserved instead of overwriting each other.
function normalizeDependencies(
  dependencies: Record<string, string> | undefined
): DependencyEdge[] {
  if (!dependencies) return [];

  return Object.entries(dependencies).map(([name, spec]) =>
    normalizeDescriptor(name, spec)
  );
}
