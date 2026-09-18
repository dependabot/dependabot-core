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

// A single `name -> requirement` edge of the dependency graph. The name is the
// real package name (npm aliases are resolved) and the requirement is a plain
// semver range, unless the descriptor uses a protocol we can't express as a
// semver range, in which case it is kept verbatim.
export interface DependencyEdge {
  name: string;
  requirement: string;
}

export interface NormalizedLockfileEntry {
  version: string;
  resolved?: string;
  dependencies: DependencyEdge[];
}

// Parses a yarn.lock into a `name@requirement` keyed object where the keys and
// the dependency edges are normalized in the same way, so that they can be
// compared against the requirements declared in a package.json manifest (also
// normalized, via `normalizeDescriptor`).
//
// Normalizing is required because yarn berry lockfiles, which are parsed by the
// yarn v1 parser too, keep the berry protocol prefixes and may group several
// descriptors under a single key. Yarn v1 lockfiles are normalized with the
// same rules, which only affects npm aliases (`alias@npm:real-pkg@^1.0.0`).
export async function parseNormalized(
  directory: string
): Promise<Record<string, NormalizedLockfileEntry>> {
  return normalizeLockfile(await parse(directory));
}

// Resolves a `name`/`requirement` descriptor pair into a dependency edge,
// stripping the `npm:` protocol and resolving npm aliases (e.g.
// `alias@npm:real-pkg@^1.0.0` becomes `real-pkg@^1.0.0`).
//
// Requirements using a protocol we can't express as a semver range
// (`workspace:`, `patch:`, `file:`, git, ...) are kept verbatim so that the
// descriptor still matches its lockfile entry, which is normalized identically.
export function normalizeDescriptor(
  name: string,
  requirement: string
): DependencyEdge {
  if (requirement.startsWith(NPM_PROTOCOL)) {
    const rest = requirement.slice(NPM_PROTOCOL.length);
    const aliasMatch = rest.match(LOCKFILE_ENTRY_REGEX);
    // An alias always carries both a package name and a requirement, e.g.
    // `npm:real-pkg@^1.0.0`. A plain requirement such as `npm:^1.0.0` has no
    // package name to extract.
    if (aliasMatch && aliasMatch[2]) {
      return { name: aliasMatch[1], requirement: aliasMatch[2] };
    }
    return { name, requirement: rest };
  }

  return { name, requirement };
}

export function edgeKey(edge: DependencyEdge): string {
  return `${edge.name}@${edge.requirement}`;
}

function normalizeLockfile(
  lockfileJson: Record<string, LockfileEntry>
): Record<string, NormalizedLockfileEntry> {
  const normalized: Record<string, NormalizedLockfileEntry> = {};

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
      normalized[edgeKey(edge)] = {
        version: pkg.version,
        resolved: pkg.resolved,
        dependencies: [...dependencies],
      };
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
