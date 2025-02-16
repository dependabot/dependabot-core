const parse = require("@dependabot/yarn-lib/lib/lockfile/parse").default;
const stringify = require("@dependabot/yarn-lib/lib/lockfile/stringify")
  .default;
const semver = require("semver");
const { LOCKFILE_ENTRY_REGEX } = require("./helpers");

function flattenIndirectDependencies(packages) {
  return (packages || []).reduce((acc, { pkg }) => {
    if ("dependencies" in pkg) {
      return acc.concat(Object.keys(pkg.dependencies));
    }
    return acc;
  }, []);
}

// Inspired by yarn-deduplicate. Altered to ensure the latest version is always used
// for version ranges which allow it.
module.exports = (data, updatedDependencyName) => {
  if (!updatedDependencyName) {
    throw new Error("Yarn fix duplicates: must provide dependency name");
  }

  const json = parse(data).object;
  const enableLockfileVersions = Boolean(data.match(/^# yarn v/m));
  const noHeader = !Boolean(data.match(/^# THIS IS AN AU/m));

  const packages = {};

  Object.entries(json).forEach(([name, pkg]) => {
    if (name.match(LOCKFILE_ENTRY_REGEX)) {
      const [_, packageName, requestedVersion] = name.match(
        LOCKFILE_ENTRY_REGEX
      );
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
      const versions = packages.map((p) => p.pkg.version).sort(semver.rcompare);
      const ranges = packages.map((p) => p.requestedVersion);

      // Dedup each package to its maxSatisfying version
      packages.forEach((p) => {
        const targetVersion = semver.maxSatisfying(
          versions,
          p.requestedVersion
        );
        if (targetVersion === null) return;
        if (targetVersion !== p.pkg.version) {
          const dedupedPackage = packages.find(
            (p) => p.pkg.version === targetVersion
          );
          json[`${name}@${p.requestedVersion}`] = dedupedPackage.pkg;
        }
      });
    });

  return stringify(json, noHeader, enableLockfileVersions);
};
