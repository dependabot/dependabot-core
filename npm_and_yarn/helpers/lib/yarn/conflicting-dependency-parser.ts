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
  normalizeDependencyEdge,
  findEntries,
  edgeKey,
  type DependencyEdge,
  type NormalizedLockfileEntry,
} from "./lockfile-parser.js";
import { LOCKFILE_ENTRY_REGEX } from "./helpers.js";
import { findLegacyConflictingDependencies } from "./legacy-conflicting-dependency-parser.js";

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

const PATCH_PROTOCOL = "patch:";
const WORKSPACE_PROTOCOL = "workspace:";

export async function findConflictingDependencies(
  directory: string,
  depName: string,
  targetVersion: string,
  enableNormalizedTraversal = false
): Promise<ConflictingDependency[]> {
  if (!enableNormalizedTraversal) {
    return findLegacyConflictingDependencies(directory, depName, targetVersion);
  }

  return findNormalizedConflictingDependencies(
    directory,
    depName,
    targetVersion
  );
}

async function findNormalizedConflictingDependencies(
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

  // Normalize manifest requirements to match lockfile descriptors.
  const topLevelEdges = topLevelDependencies.map(([name, requirement]) =>
    normalizeDependencyEdge(name, requirement, lockfileJson)
  );
  const topLevelWorkspaceNames = new Set(
    topLevelEdges
      .filter((edge) => edge.requirement.startsWith(WORKSPACE_PROTOCOL))
      .map((edge) => edge.name)
  );

  const manifestConflictingParents = topLevelEdges.flatMap((topLevelEdge) => {
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
  });

  // Workspaces are independent dependency roots, but their manifest
  // constraints are not dependency blockers. Traverse from each workspace's
  // dependencies while retaining the workspace as the top-level context. The
  // root workspace and manifest dependencies are already covered above.
  const traversedWorkspaceNames = new Set(topLevelWorkspaceNames);
  const workspaceConflictingParents = lockfileJson
    .filter((entry) => {
      if (
        !entry.requirement.startsWith(WORKSPACE_PROTOCOL) ||
        entry.requirement === `${WORKSPACE_PROTOCOL}.` ||
        traversedWorkspaceNames.has(entry.name)
      ) {
        return false;
      }

      traversedWorkspaceNames.add(entry.name);
      return true;
    })
    .flatMap((workspace) => {
      const topLevelSpec: TopLevelSpec = {
        name: workspace.name,
        requirement: workspace.requirement,
        realName: workspace.realName ?? workspace.name,
        version: workspace.version,
      };
      const transitiveSpec: TransitiveSpec = {
        name: workspace.name,
        requirement: workspace.requirement,
        realName: workspace.realName ?? workspace.name,
        version: workspace.version,
      };

      return workspace.dependencies.flatMap((dependency) =>
        Array.from(
          findConflictingParentDependencies(
            dependency,
            depName,
            targetVersion,
            { ...topLevelSpec },
            lockfileJson,
            { ...transitiveSpec }
          ).values()
        )
      );
    });

  const conflictingParents = [
    ...manifestConflictingParents,
    ...workspaceConflictingParents,
  ];

  // Collapse identical output while preserving each independent ancestor that
  // must be updated.
  const conflicts = new Map<string, ConflictingDependency>();
  for (const parentSpec of conflictingParents) {
    const conflict = {
      explanation: buildExplanation(parentSpec, depName),
      name: realNameOf(parentSpec),
      version: parentSpec.version,
      requirement: parentSpec.requirement,
    };
    const key = [
      conflict.explanation,
      conflict.name,
      conflict.version,
      conflict.requirement,
    ].join("\u0000");
    if (conflicts.has(key)) continue;

    conflicts.set(key, conflict);
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

function realRequirementOf(edge: DependencyEdge): string {
  const { requirement, realName } = edge;
  if (requirement.startsWith(PATCH_PROTOCOL)) {
    const source = requirement.slice(PATCH_PROTOCOL.length).split("#", 1)[0];
    const nestedNpmDescriptor = source.match(/@npm%3A(.+)$/i);
    if (nestedNpmDescriptor) {
      return decodeURIComponent(nestedNpmDescriptor[1]);
    }
  }

  if (!requirement.startsWith("npm:")) return requirement;

  const rest = requirement.slice("npm:".length);
  const aliasMatch = rest.match(LOCKFILE_ENTRY_REGEX);
  if (aliasMatch && aliasMatch[2]) {
    return aliasMatch[2];
  }
  if (realName === rest) return "*";

  return rest;
}

function conflictsWith(targetVersion: string, edge: DependencyEdge): boolean {
  if (edge.requirement.startsWith(WORKSPACE_PROTOCOL)) return false;

  const requirement = realRequirementOf(edge);
  if (!semver.validRange(requirement)) return true;

  return !semver.satisfies(targetVersion, requirement);
}

function findConflictingParentDependencies(
  edge: DependencyEdge,
  targetDep: string,
  targetversion: string,
  topLevelSpec: TopLevelSpec,
  lockfile: NormalizedLockfileEntry[],
  transitiveSpec: TransitiveSpec = {} as TransitiveSpec,
  shortestDepthByEntry: Map<string, number> = new Map(),
  conflictingParents: Map<string, ParentSpec> = new Map(),
  depth = 0
): Map<string, ParentSpec> {
  const checkedEntry = edgeKey(edge);
  const shortestDepth = shortestDepthByEntry.get(checkedEntry);
  if (shortestDepth !== undefined && shortestDepth <= depth) {
    return conflictingParents;
  }

  shortestDepthByEntry.set(checkedEntry, depth);

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
        conflictsWith(targetversion, subDep)
      ) {
        // Only add the conflicting parent once per version preventing
        // duplicate dependencies from circular graphs.
        const requirement = realRequirementOf(subDep);
        const key = [realNameOf(pkg), pkg.version, requirement].join("\u0000");
        // Snapshot the top-level spec because its installed version is
        // decorated while traversing lockfile entries.
        conflictingParents.set(key, {
          name: realNameOf(pkg),
          version: pkg.version,
          requirement,
          realName: pkg.realName ?? pkg.name,
          transitiveSpec: { ...transitiveSpec },
          topLevelSpec: { ...topLevelSpec },
        });
      } else {
        // Keep track of the parent dependency as a way to check if the
        // conflicting dependency ends up being a direct dependency of a
        // top-level dependency
        const nextTransitiveSpec = {
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
          nextTransitiveSpec,
          shortestDepthByEntry,
          conflictingParents,
          depth + 1
        );
      }
    }
  }

  return conflictingParents;
}
