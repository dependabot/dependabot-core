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
import { readFile, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const YAML_DOCUMENT_START = "---\n";
const YAML_DOCUMENT_SEPARATOR = "\n---\n";

interface PnpmDependency {
  name: string;
  version: string;
  resolved: string | undefined;
  dev: boolean;
  specifiers: string[];
  aliased: boolean;
}

export async function parse(directory: string): Promise<PnpmDependency[]> {
  const lockfile = await readLockfile(directory);

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

async function readLockfile(directory: string) {
  const content = await readLockfileContent(directory);
  // pnpm 11 can prepend an environment lockfile before the project lockfile.
  const mainDocument = content === null ? null : extractMainDocument(content);

  if (mainDocument === null) {
    return readWantedLockfile(directory, {
      ignoreIncompatible: true,
    });
  }

  const tempDirectory = await mkdtemp(
    path.join(os.tmpdir(), "dependabot-pnpm-lockfile-")
  );

  try {
    await writeFile(
      path.join(tempDirectory, "pnpm-lock.yaml"),
      mainDocument,
      "utf8"
    );
    return await readWantedLockfile(tempDirectory, {
      ignoreIncompatible: true,
    });
  } finally {
    await rm(tempDirectory, { recursive: true, force: true });
  }
}

async function readLockfileContent(directory: string): Promise<string | null> {
  try {
    return await readFile(path.join(directory, "pnpm-lock.yaml"), "utf8");
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      return null;
    }

    throw error;
  }
}

function extractMainDocument(content: string): string | null {
  content = content.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
  if (!content.startsWith(YAML_DOCUMENT_START)) {
    return null;
  }

  const separatorIndex = content.indexOf(
    YAML_DOCUMENT_SEPARATOR,
    YAML_DOCUMENT_START.length
  );
  if (separatorIndex === -1) {
    return null;
  }

  return content.slice(separatorIndex + YAML_DOCUMENT_SEPARATOR.length);
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

    if (
      Object.values(projectSpecifiers).some(
        (specifier) =>
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
