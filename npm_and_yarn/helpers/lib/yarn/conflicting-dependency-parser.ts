/* Conflicting dependency parser for yarn
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - target dependency version
 *
 * Outputs:
 *  - An array of objects with conflicting dependencies
 */

import fs from "fs";
import path from "path";
import semver from "semver";
import {
  parseNormalized,
  normalizeRequirement,
  type LockfileEntry,
} from "./lockfile-parser.js";
import { LOCKFILE_ENTRY_REGEX } from "./helpers.js";

interface ConflictingDependency {
  explanation: string;
  name: string;
  version: string;
  requirement: string;
}

interface ParentSpec {
  name: string;
  version: string;
  requirement: string;
  transitiveSpec: TransitiveSpec;
  topLevelSpec: TopLevelSpec;
}

interface TopLevelSpec {
  name: string;
  requirement: string;
  version?: string;
}

interface TransitiveSpec {
  name: string;
  version: string;
  requirement?: string;
}

export async function findConflictingDependencies(
  directory: string,
  depName: string,
  targetVersion: string
): Promise<ConflictingDependency[]> {
  const lockfileJson = await parseNormalized(directory);
  const packageJson = fs
    .readFileSync(path.join(directory, "package.json"))
    .toString();
  const dependencyTypes = [
    "dependencies",
    "devDependencies",
    "optionalDependencies",
  ];
  const topLevelDependencies: [string, string][] = dependencyTypes.flatMap(
    (type) => {
      return Object.entries(JSON.parse(packageJson)[type] || {}) as [
        string,
        string,
      ][];
    }
  );

  const conflictingParents = topLevelDependencies.flatMap(
    ([topLevelDepName, rawTopLevelRequirement]) => {
      const normalized = normalizeRequirement(rawTopLevelRequirement);
      // Skip dependencies declared with a protocol we can't match against a
      // lockfile entry, e.g. `workspace:*` or `file:../pkg`.
      if (!normalized) return [];

      const name = normalized.name || topLevelDepName;
      const topLevelRequirement = normalized.requirement;
      const topLevelSpec: TopLevelSpec = {
        name,
        requirement: topLevelRequirement,
      };

      return Array.from(
        findConflictingParentDependencies(
          name,
          topLevelRequirement,
          depName,
          targetVersion,
          topLevelSpec,
          lockfileJson
        ).values()
      );
    }
  );

  return conflictingParents.map((parentSpec) => {
    const explanation = buildExplanation(parentSpec, depName);
    return {
      explanation: explanation,
      name: parentSpec.name,
      version: parentSpec.version,
      requirement: parentSpec.requirement,
    };
  });
}

function buildExplanation(
  parentSpec: ParentSpec,
  targetDepName: string
): string {
  if (
    parentSpec.name === parentSpec.topLevelSpec.name &&
    parentSpec.version === parentSpec.topLevelSpec.version
  ) {
    // The nodes parent is top-level
    return (
      `${parentSpec.name}@${parentSpec.version} requires ${targetDepName}` +
      `@${parentSpec.requirement}`
    );
  } else if (
    parentSpec.transitiveSpec.name === parentSpec.topLevelSpec.name &&
    parentSpec.transitiveSpec.version === parentSpec.topLevelSpec.version
  ) {
    // The nodes parent is a direct dependency of the top-level dependency
    return (
      `${parentSpec.topLevelSpec.name}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via ${parentSpec.name}@${parentSpec.version}`
    );
  } else {
    // The nodes parent is a transitive dependency of the top-level dependency
    return (
      `${parentSpec.topLevelSpec.name}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via a transitive dependency on ${parentSpec.name}@${parentSpec.version}`
    );
  }
}

// A dependency only conflicts if it declares a semver range that excludes the
// target version. Specs we can't parse as a semver range (e.g. yarn berry
// `patch:` or `workspace:` protocols) are not treated as conflicts.
function conflictsWith(targetVersion: string, spec: string): boolean {
  if (!semver.validRange(spec)) return false;

  return !semver.satisfies(targetVersion, spec);
}

function findConflictingParentDependencies(
  dependency: string,
  requirement: string,
  targetDep: string,
  targetversion: string,
  topLevelSpec: TopLevelSpec,
  lockfileJson: Record<string, LockfileEntry>,
  transitiveSpec: TransitiveSpec = {} as TransitiveSpec,
  checkedEntries: Set<string> = new Set(),
  conflictingParents: Map<string, ParentSpec> = new Map()
): Map<string, ParentSpec> {
  // Prevent infinite loops for circular dependencies by only checking each
  // lockfile entry once
  const checkedEntry = [dependency, requirement].join("@");
  if (checkedEntries.has(checkedEntry)) {
    return conflictingParents;
  }

  checkedEntries.add(checkedEntry);

  for (const [entry, pkg] of Object.entries(lockfileJson)) {
    const match = entry.match(LOCKFILE_ENTRY_REGEX);
    if (!match) continue;
    const [, parentDepName, parentDepRequirement] = match;
    // Decorate the top-level dependency spec with an installed version as we
    // only have the requirement from the package.json manifest
    if (
      topLevelSpec.name == parentDepName &&
      topLevelSpec.requirement == parentDepRequirement
    ) {
      topLevelSpec.version = pkg.version;
    }

    if (
      pkg.dependencies &&
      dependency == parentDepName &&
      requirement == parentDepRequirement
    ) {
      // Recursive check for sub-dependencies finding dependencies that don't
      // allow the target version of the vulnerable dependency to be installed
      for (const [subDepName, spec] of Object.entries(pkg.dependencies) as [
        string,
        string,
      ][]) {
        if (subDepName === targetDep && conflictsWith(targetversion, spec)) {
          // Only add the conflicting parent once per version preventing
          // duplicate dependencies from circular graphs
          const key = [parentDepName, pkg.version].join("@");
          conflictingParents.set(key, {
            name: parentDepName,
            version: pkg.version,
            requirement: spec,
            transitiveSpec,
            topLevelSpec,
          });
        } else {
          // Keep track of the parent dependency as a way to check if the
          // conflicting dependency ends up being a direct dependency of a
          // top-level dependency
          transitiveSpec = {
            name: parentDepName,
            version: pkg.version,
            requirement: parentDepRequirement,
          };
          findConflictingParentDependencies(
            subDepName,
            spec,
            targetDep,
            targetversion,
            topLevelSpec,
            lockfileJson,
            transitiveSpec,
            checkedEntries,
            conflictingParents
          );
        }
      }
    }
  }

  return conflictingParents;
}
