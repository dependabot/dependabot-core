import fs from "fs";
import path from "path";
import semver from "semver";
import { parse, type LockfileEntry } from "./lockfile-parser.js";
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

export async function findLegacyConflictingDependencies(
  directory: string,
  depName: string,
  targetVersion: string
): Promise<ConflictingDependency[]> {
  const lockfileJson = await parse(directory);
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
    ([topLevelDepName, topLevelRequirement]) => {
      const topLevelSpec: TopLevelSpec = {
        name: topLevelDepName,
        requirement: topLevelRequirement,
      };

      return Array.from(
        findConflictingParentDependencies(
          topLevelDepName,
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
      explanation,
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
    return (
      `${parentSpec.name}@${parentSpec.version} requires ${targetDepName}` +
      `@${parentSpec.requirement}`
    );
  } else if (
    parentSpec.transitiveSpec.name === parentSpec.topLevelSpec.name &&
    parentSpec.transitiveSpec.version === parentSpec.topLevelSpec.version
  ) {
    return (
      `${parentSpec.topLevelSpec.name}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via ${parentSpec.name}@${parentSpec.version}`
    );
  } else {
    return (
      `${parentSpec.topLevelSpec.name}@${parentSpec.topLevelSpec.version} requires ` +
      `${targetDepName}@${parentSpec.requirement} ` +
      `via a transitive dependency on ${parentSpec.name}@${parentSpec.version}`
    );
  }
}

function findConflictingParentDependencies(
  dependency: string,
  requirement: string,
  targetDep: string,
  targetVersion: string,
  topLevelSpec: TopLevelSpec,
  lockfileJson: Record<string, LockfileEntry>,
  transitiveSpec: TransitiveSpec = {} as TransitiveSpec,
  checkedEntries: Set<string> = new Set(),
  conflictingParents: Map<string, ParentSpec> = new Map()
): Map<string, ParentSpec> {
  const checkedEntry = [dependency, requirement].join("@");
  if (checkedEntries.has(checkedEntry)) {
    return conflictingParents;
  }

  checkedEntries.add(checkedEntry);

  for (const [entry, pkg] of Object.entries(lockfileJson)) {
    const match = entry.match(LOCKFILE_ENTRY_REGEX);
    if (!match) continue;
    const [, parentDepName, parentDepRequirement] = match;

    if (
      topLevelSpec.name === parentDepName &&
      topLevelSpec.requirement === parentDepRequirement
    ) {
      topLevelSpec.version = pkg.version;
    }

    if (
      pkg.dependencies &&
      dependency === parentDepName &&
      requirement === parentDepRequirement
    ) {
      for (const [subDepName, spec] of Object.entries(pkg.dependencies)) {
        if (
          subDepName === targetDep &&
          !semver.satisfies(targetVersion, spec)
        ) {
          const key = [parentDepName, pkg.version].join("@");
          conflictingParents.set(key, {
            name: parentDepName,
            version: pkg.version,
            requirement: spec,
            transitiveSpec,
            topLevelSpec,
          });
        } else {
          transitiveSpec = {
            name: parentDepName,
            version: pkg.version,
            requirement: parentDepRequirement,
          };
          findConflictingParentDependencies(
            subDepName,
            spec,
            targetDep,
            targetVersion,
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
