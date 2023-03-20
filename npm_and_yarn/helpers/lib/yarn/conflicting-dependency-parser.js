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

const fs = require("fs");
const path = require("path");
const semver = require("semver");
const { parse } = require("./lockfile-parser");
const { LOCKFILE_ENTRY_REGEX } = require("./helpers");

async function findConflictingDependencies(directory, depName, targetVersion) {
  const lockfileJson = await parse(directory);
  const packageJson = fs
    .readFileSync(path.join(directory, "package.json"))
    .toString();
  const dependencyTypes = [
    "dependencies",
    "devDependencies",
    "optionalDependencies",
  ];
  const topLevelDependencies = dependencyTypes.flatMap((type) => {
    return Object.entries(JSON.parse(packageJson)[type] || {});
  });

  const conflictingParents = topLevelDependencies.flatMap(
    ([topLevelDepName, topLevelRequirement]) => {
      const topLevelSpec = {
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
      explanation: explanation,
      name: parentSpec.name,
      version: parentSpec.version,
      requirement: parentSpec.requirement,
    };
  });
}

function buildExplanation(parentSpec, targetDepName) {
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

function findConflictingParentDependencies(
  dependency,
  requirement,
  targetDep,
  targetversion,
  topLevelSpec,
  lockfileJson,
  transitiveSpec = {},
  checkedEntries = new Set(),
  conflictingParents = new Map()
) {
  // Prevent infinte loops for circular dependencies by only checking each
  // lockfile entry once
  const checkedEntry = [dependency, requirement].join("@");
  if (checkedEntries.has(checkedEntry)) {
    return conflictingParents;
  }

  checkedEntries.add(checkedEntry);

  for (const [entry, pkg] of Object.entries(lockfileJson)) {
    const [_, parentDepName, parentDepRequirement] = entry.match(
      LOCKFILE_ENTRY_REGEX
    );
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
      for (const [subDepName, spec] of Object.entries(pkg.dependencies)) {
        if (
          subDepName === targetDep &&
          !semver.satisfies(targetversion, spec)
        ) {
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

module.exports = { findConflictingDependencies };
