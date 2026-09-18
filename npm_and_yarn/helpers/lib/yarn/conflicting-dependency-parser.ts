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
  normalizeDescriptor,
  findEntries,
  edgeKey,
  type DependencyEdge,
  type NormalizedLockfileEntry,
} from "./lockfile-parser.js";

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
      // Normalize the manifest requirement the same way the lockfile entries
      // are normalized, so that aliases and yarn berry protocols match up.
      const topLevelEdge = normalizeDescriptor(
        topLevelDepName,
        rawTopLevelRequirement
      );
      const topLevelSpec: TopLevelSpec = {
        name: topLevelEdge.name,
        requirement: topLevelEdge.requirement,
      };

      return Array.from(
        findConflictingParentDependencies(
          topLevelEdge,
          depName,
          targetVersion,
          topLevelSpec,
          lockfileJson
        ).values()
      );
    }
  );

  // The same blocking dependency can be reached through several top-level
  // dependencies (e.g. a package and an npm alias of it), so it is only
  // reported once.
  const conflicts = new Map<string, ConflictingDependency>();
  for (const parentSpec of conflictingParents) {
    const key = [
      parentSpec.name,
      parentSpec.version,
      parentSpec.requirement,
    ].join("\u0000");
    if (conflicts.has(key)) continue;

    conflicts.set(key, {
      explanation: buildExplanation(parentSpec, depName),
      name: parentSpec.name,
      version: parentSpec.version,
      requirement: parentSpec.requirement,
    });
  }

  return Array.from(conflicts.values());
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
  edge: DependencyEdge,
  targetDep: string,
  targetversion: string,
  topLevelSpec: TopLevelSpec,
  lockfile: NormalizedLockfileEntry[],
  transitiveSpec: TransitiveSpec = {} as TransitiveSpec,
  checkedEntries: Set<string> = new Set(),
  conflictingParents: Map<string, ParentSpec> = new Map()
): Map<string, ParentSpec> {
  // Prevent infinite loops for circular dependencies by only checking each
  // lockfile entry once
  const checkedEntry = edgeKey(edge);
  if (checkedEntries.has(checkedEntry)) {
    return conflictingParents;
  }

  checkedEntries.add(checkedEntry);

  // A descriptor can resolve to more than one entry, e.g. when a manifest
  // depends on both a package and an npm alias of it, so every resolution is
  // traversed.
  const isTopLevelEdge = checkedEntry === edgeKey(topLevelSpec);

  for (const pkg of findEntries(lockfile, edge)) {
    // Decorate the top-level dependency spec with an installed version as we
    // only have the requirement from the package.json manifest
    if (isTopLevelEdge) topLevelSpec.version = pkg.version;

    // Recursive check for sub-dependencies finding dependencies that don't
    // allow the target version of the vulnerable dependency to be installed
    for (const subDep of pkg.dependencies) {
      if (
        subDep.name === targetDep &&
        conflictsWith(targetversion, subDep.requirement)
      ) {
        // Only add the conflicting parent once per version preventing
        // duplicate dependencies from circular graphs
        const key = [pkg.name, pkg.version].join("@");
        // Snapshot the specs as they are mutated while traversing the other
        // resolutions of this descriptor.
        conflictingParents.set(key, {
          name: pkg.name,
          version: pkg.version,
          requirement: subDep.requirement,
          transitiveSpec: { ...transitiveSpec },
          topLevelSpec: { ...topLevelSpec },
        });
      } else {
        // Keep track of the parent dependency as a way to check if the
        // conflicting dependency ends up being a direct dependency of a
        // top-level dependency
        transitiveSpec = {
          name: pkg.name,
          version: pkg.version,
          requirement: pkg.requirement,
        };
        findConflictingParentDependencies(
          subDep,
          targetDep,
          targetversion,
          topLevelSpec,
          lockfile,
          transitiveSpec,
          checkedEntries,
          conflictingParents
        );
      }
    }
  }

  return conflictingParents;
}
