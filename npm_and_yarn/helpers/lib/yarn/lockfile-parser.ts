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
const PROTOCOL_REGEX = /^[a-z0-9+.-]+:/i;

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

// Parses a yarn.lock into a normalized `name@requirement` keyed object, where
// requirements are plain semver ranges regardless of the lockfile format.
//
// Yarn berry lockfiles are parsed by the yarn v1 parser too, but their entries
// keep the yarn berry protocol prefixes (and may group several descriptors
// under a single key), so they need normalizing before they can be compared
// against the requirements declared in a package.json manifest.
export async function parseNormalized(
  directory: string
): Promise<Record<string, LockfileEntry>> {
  const lockfileJson = await parse(directory);
  if (!isBerryLockfile(lockfileJson)) return lockfileJson;

  return normalizeBerryLockfile(lockfileJson);
}

export function isBerryLockfile(
  lockfileJson: Record<string, LockfileEntry>
): boolean {
  return Object.prototype.hasOwnProperty.call(lockfileJson, METADATA_KEY);
}

// Strips the `npm:` protocol from a yarn berry requirement, resolving npm
// aliases (e.g. `npm:real-pkg@^1.0.0`) to the aliased package name and
// requirement. Returns `null` for requirements using a protocol we can't
// compare against a semver range (`workspace:`, `patch:`, `file:`, git, ...).
export function normalizeRequirement(
  requirement: string
): { name?: string; requirement: string } | null {
  if (requirement.startsWith(NPM_PROTOCOL)) {
    const rest = requirement.slice(NPM_PROTOCOL.length);
    const aliasMatch = rest.match(LOCKFILE_ENTRY_REGEX);
    // An alias always carries both a package name and a requirement, e.g.
    // `npm:real-pkg@^1.0.0`. A plain requirement such as `npm:^1.0.0` has no
    // package name to extract.
    if (aliasMatch && aliasMatch[2]) {
      return { name: aliasMatch[1], requirement: aliasMatch[2] };
    }
    return { requirement: rest };
  }

  if (PROTOCOL_REGEX.test(requirement)) return null;

  return { requirement };
}

function normalizeBerryLockfile(
  lockfileJson: Record<string, LockfileEntry>
): Record<string, LockfileEntry> {
  const normalized: Record<string, LockfileEntry> = {};

  for (const [entry, pkg] of Object.entries(lockfileJson)) {
    if (entry === METADATA_KEY) continue;

    const normalizedPkg: LockfileEntry = {
      ...pkg,
      ...(pkg.dependencies
        ? { dependencies: normalizeDependencies(pkg.dependencies) }
        : {}),
    };

    for (const descriptor of entry.split(DESCRIPTOR_SEPARATOR)) {
      const match = descriptor.match(LOCKFILE_ENTRY_REGEX);
      if (!match) continue;

      const [, name, requirement] = match;
      const normalizedRequirement = normalizeRequirement(requirement);
      // Skip entries we can't express as a semver requirement, e.g. workspace
      // packages and patched dependencies.
      if (!normalizedRequirement) continue;

      const normalizedName = normalizedRequirement.name || name;
      normalized[`${normalizedName}@${normalizedRequirement.requirement}`] =
        normalizedPkg;
    }
  }

  return normalized;
}

function normalizeDependencies(
  dependencies: Record<string, string>
): Record<string, string> {
  const normalized: Record<string, string> = {};

  for (const [name, spec] of Object.entries(dependencies)) {
    const normalizedSpec = normalizeRequirement(spec);
    if (!normalizedSpec) {
      // Keep unsupported protocols verbatim so that callers can decide how to
      // handle them rather than silently dropping the dependency.
      normalized[name] = spec;
      continue;
    }

    normalized[normalizedSpec.name || name] = normalizedSpec.requirement;
  }

  return normalized;
}
