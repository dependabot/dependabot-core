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
  realName?: string;
  transitiveSpec: TransitiveSpec;
  topLevelSpec: TopLevelSpec;
}

interface TopLevelSpec {
  name: string;
  requirement: string;
  realName?: string;
  version?: string;
}

interface TransitiveSpec {
  name: string;
  version: string;
  requirement?: string;
  realName?: string;
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
        realName: topLevelEdge.realName ?? topLevelEdge.name,
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
      realNameOf(parentSpec),
      parentSpec.version,
      parentSpec.requirement,
    ].join("\u0000");
    if (conflicts.has(key)) continue;

    conflicts.set(key, {
      explanation: buildExplanation(parentSpec, depName),
      name: realNameOf(parentSpec),
      version: parentSpec.version,
      requirement: parentSpec.requirement,
    });
  }

  return Array.from(conflicts.values());
}

function realNameOf(edge: { name: string; realName?: string }): string {
  return edge.realName ?? edge.name;
}

function buildExplanation(
  parentSpec: ParentSpec,
  targetDepName: string
): string {
  const parentName = realNameOf(parentSpec);
  const topLevelName = realNameOf(parentSpec.topLevelSpec);

  if (
    parentName === topLevelName &&
    parentSpec.version === parentSpec.topLevelSpec.version
  ) {
    // The node's parent is top-level.
    return (
      `${parentName}@${parentSpec.version} requires ${targetDepName}` +
      `@${parentSpec.requirement}`
    );
  } else if (
    realNameOf(parentSpec.transitiveSpec) === topLevelName &&
    parentSpec.transitiveSpec.version === parentSpec.topLevelSpec.version
  ) {
    // The node's parent is a direct dependency of the top-level dependency.
    return (
      `${topLevelName}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via ${parentName}@${parentSpec.version}`
    );
  } else {
    // The node's parent is a transitive dependency of the top-level dependency.
    return (
      `${topLevelName}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via a transitive dependency on ${parentName}@${parentSpec.version}`
    );
  }
}

// A dependency only conflicts if it declares a semver range that excludes the
// target version. Specs we can't parse as a semver range (e.g. yarn berry
// `patch:` or `workspace:` protocols) are not treated as conflicts.
function realRequirementOf(requirement: string): string {
  if (!requirement.startsWith("npm:")) return requirement;

  const rest = requirement.slice("npm:".length);
  const aliasMatch = rest.match(LOCKFILE_ENTRY_REGEX);
  if (aliasMatch && aliasMatch[2]) {
    return aliasMatch[2];
  }

  return rest;
}

function conflictsWith(targetVersion: string, spec: string): boolean {
  const requirement = realRequirementOf(spec);
  if (!semver.validRange(requirement)) return false;

  return !semver.satisfies(targetVersion, requirement);
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
        realNameOf(subDep) === targetDep &&
        conflictsWith(targetversion, subDep.requirement)
      ) {
        // Only add the conflicting parent once per version preventing
        // duplicate dependencies from circular graphs.
        const key = [realNameOf(pkg), pkg.version].join("@");
        // Snapshot the specs as they are mutated while traversing the other
        // resolutions of this descriptor.
        conflictingParents.set(key, {
          name: realNameOf(pkg),
          version: pkg.version,
          requirement: realRequirementOf(subDep.requirement),
          realName: pkg.realName ?? pkg.name,
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
          realName: pkg.realName ?? pkg.name,
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
