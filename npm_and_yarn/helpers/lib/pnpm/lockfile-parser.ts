/* PNPM-LOCK.YAML PARSER
 *
 * Inputs:
 *  - directory containing a pnpm-lock.yaml file
 *
 * Outputs:
 *  - JSON formatted information of dependencies (name, version, dependency-type)
 */

import {
  readWantedLockfile,
  type PackageSnapshot,
  type ProjectSnapshot,
} from "@pnpm/lockfile-file";
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
    .filter(([depPath]) => {
      const dp = dependencyPath.parse(depPath);
      return dp && dp.name; // null or undefined checked for dependency path (dp) and empty name dps are filtered.
    })
    .map(([depPath, pkgSnapshot]: [string, PackageSnapshot]) =>
      nameVerDevFromPkgSnapshot(
        depPath,
        pkgSnapshot,
        Object.values(lockfile.importers)
      )
    );
}

function nameVerDevFromPkgSnapshot(
  depPath: string,
  pkgSnapshot: PackageSnapshot,
  projectSnapshots: ProjectSnapshot[]
): PnpmDependency {
  let name: string;
  let version: string;

  if (!pkgSnapshot.name) {
    const pkgInfo = dependencyPath.parse(depPath);
    name = pkgInfo.name ?? depPath;
    version = pkgInfo.version ?? "";
  } else {
    name = pkgSnapshot.name;
    version = pkgSnapshot.version ?? "";
  }

  const specifiers: string[] = [];
  let aliased = false;

  projectSnapshots.every((projectSnapshot) => {
    const projectSpecifiers = projectSnapshot.specifiers;

    // Check if this specific package version was brought in via an alias.
    // We only mark it as aliased if there is NO direct specifier for this name
    // that resolves to this version — meaning it must have been brought in
    // through an npm: alias specifier on a different key.
    const currentSpecifier = projectSpecifiers[name];

    if (currentSpecifier) {
      // There's a direct specifier for this package name — check if it
      // resolves to this version
      const specifierVersion =
        projectSnapshot.dependencies?.[name] ||
        projectSnapshot.devDependencies?.[name] ||
        projectSnapshot.optionalDependencies?.[name];

      if (
        specifierVersion &&
        (specifierVersion == version ||
          specifierVersion.startsWith(`${version}_`) || // lockfileVersion 5.4
          specifierVersion.startsWith(`${version}(`)) // lockfileVersion 6.0
      ) {
        specifiers.push(currentSpecifier);
        return true;
      }
    }

    // No direct specifier matched this version — check if it's aliased
    if (
      Object.values(projectSpecifiers).some(
        (specifier) =>
          specifier.startsWith(`npm:${name}@`) || specifier == `npm:${name}`
      )
    ) {
      // Only mark as aliased if there's no direct specifier for this name,
      // or the direct specifier resolves to a different version
      aliased = true;
      return false;
    }

    return true;
  });

  return {
    name: name,
    version: version,
    resolved:
      "tarball" in pkgSnapshot.resolution
        ? pkgSnapshot.resolution.tarball
        : undefined,
    dev: "dev" in pkgSnapshot && pkgSnapshot.dev === true,
    specifiers: specifiers,
    aliased: aliased,
  };
}
