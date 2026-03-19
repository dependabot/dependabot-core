import semver from "semver";
import { LOCKFILE_ENTRY_REGEX } from "./helpers.js";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const parse = require("@dependabot/yarn-lib/lib/lockfile/parse").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const stringify =
  require("@dependabot/yarn-lib/lib/lockfile/stringify").default;

function flattenIndirectDependencies(packages: any[]): string[] {
  return (packages || []).reduce((acc: string[], { pkg }: any) => {
    if ("dependencies" in pkg) {
      return acc.concat(Object.keys(pkg.dependencies));
    }
    return acc;
  }, []);
}

// Inspired by yarn-deduplicate. Altered to ensure the latest version is always used
// for version ranges which allow it.
export default function fixDuplicates(
  data: string,
  updatedDependencyName: string
): string {
  if (!updatedDependencyName) {
    throw new Error("Yarn fix duplicates: must provide dependency name");
  }

  const json = parse(data).object;
  const enableLockfileVersions = Boolean(data.match(/^# yarn v/m));
  const noHeader = !Boolean(data.match(/^# THIS IS AN AU/m));

  const packages: Record<string, any[]> = {};

  Object.entries(json).forEach(([name, pkg]: [string, any]) => {
    if (name.match(LOCKFILE_ENTRY_REGEX)) {
      const match = name.match(LOCKFILE_ENTRY_REGEX)!;
      const [_, packageName, requestedVersion] = match;
      packages[packageName] = packages[packageName] || [];
      packages[packageName].push(
        Object.assign({}, { name, pkg, packageName, requestedVersion })
      );
    }
  });

  const packageEntries = Object.entries(packages);

  const updatedPackageEntry = packageEntries.filter(([name]) => {
    return updatedDependencyName === name;
  });

  const updatedDependencyPackage =
    updatedPackageEntry[0] && updatedPackageEntry[0][1];

  const indirectDependencies = flattenIndirectDependencies(
    updatedDependencyPackage
  );

  const packagesToDedupe = [updatedDependencyName, ...indirectDependencies];

  packageEntries
    .filter(([name]) => packagesToDedupe.includes(name))
    .forEach(([name, packages]) => {
      // Reverse sort, so we'll find the maximum satisfying version first
      const versions = packages
        .map((p: any) => p.pkg.version)
        .sort(semver.rcompare);

      // Dedup each package to its maxSatisfying version
      packages.forEach((p: any) => {
        const targetVersion = semver.maxSatisfying(
          versions,
          p.requestedVersion
        );
        if (targetVersion === null) return;
        if (targetVersion !== p.pkg.version) {
          const dedupedPackage = packages.find(
            (p: any) => p.pkg.version === targetVersion
          );
          json[`${name}@${p.requestedVersion}`] = dedupedPackage.pkg;
        }
      });
    });

  return stringify(json, noHeader, enableLockfileVersions);
}
