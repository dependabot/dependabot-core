/* PNPM-LOCK.YAML PARSER
 *
 * Inputs:
 *  - directory containing a pnpm-lock.yaml file
 *
 * Outputs:
 *  - JSON formatted information of dependencies (name, version, dependency-type)
 */

import { readWantedLockfile } from "@pnpm/lockfile-file";
import * as dependencyPath from "@pnpm/dependency-path";

interface PnpmDependency {
  name: string;
  version: string;
  resolved: string | undefined;
  dev: boolean;
  specifiers: string[];
  aliased: boolean;
}

export async function parse(directory: string): Promise<PnpmDependency[]> {
  const lockfile = await readWantedLockfile(directory, {
    ignoreIncompatible: true,
  });

  if (!lockfile) {
    return [];
  }

  return Object.entries(lockfile.packages ?? {})
    .filter(([depPath]: [string, any]) => {
      const dp = dependencyPath.parse(depPath);
      return dp && dp.name; // null or undefined checked for dependency path (dp) and empty name dps are filtered.
    })
    .map(([depPath, pkgSnapshot]: [string, any]) =>
      nameVerDevFromPkgSnapshot(
        depPath,
        pkgSnapshot,
        Object.values(lockfile.importers)
      )
    );
}

function nameVerDevFromPkgSnapshot(
  depPath: string,
  pkgSnapshot: any,
  projectSnapshots: any[]
): PnpmDependency {
  let name: string;
  let version: string;

  if (!pkgSnapshot.name) {
    const pkgInfo = dependencyPath.parse(depPath);
    name = pkgInfo.name ?? depPath;
    version = pkgInfo.version ?? "";
  } else {
    name = pkgSnapshot.name;
    version = pkgSnapshot.version;
  }

  const specifiers: string[] = [];
  let aliased = false;

  projectSnapshots.every((projectSnapshot: any) => {
    const projectSpecifiers = projectSnapshot.specifiers;

    if (
      Object.values(projectSpecifiers).some(
        (specifier: any) =>
          specifier.startsWith(`npm:${name}@`) || specifier == `npm:${name}`
      )
    ) {
      aliased = true;
      return false;
    }

    const currentSpecifier = projectSpecifiers[name];

    if (!currentSpecifier) {
      return true;
    }

    let specifierVersion = currentSpecifier.version;

    if (!currentSpecifier.version) {
      specifierVersion =
        projectSnapshot.dependencies?.[name] ||
        projectSnapshot.devDependencies?.[name] ||
        projectSnapshot.optionalDependencies?.[name];
    }

    if (
      specifierVersion == version ||
      specifierVersion.startsWith(`${version}_`) || // lockfileVersion 5.4
      specifierVersion.startsWith(`${version}(`) // lockfileVersion 6.0
    ) {
      specifiers.push(currentSpecifier.specifier || currentSpecifier);
    }

    return true;
  });

  return {
    name: name,
    version: version,
    resolved: pkgSnapshot.resolution.tarball,
    dev: pkgSnapshot.dev,
    specifiers: specifiers,
    aliased: aliased,
  };
}
