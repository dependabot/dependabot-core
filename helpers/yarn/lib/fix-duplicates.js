const fs = require("fs");
const parse = require("@dependabot/yarn-lib/lib/lockfile/parse").default;
const stringify = require("@dependabot/yarn-lib/lib/lockfile/stringify")
  .default;
const semver = require("semver");

// Credit: https://bitbucket.org/atlassian/yarn-tools
module.exports = (data, includePackages = []) => {
  const json = parse(data).object;
  const enableLockfileVersions = Boolean(data.match(/^# yarn v/m));
  const noHeader = !Boolean(data.match(/^# THIS IS AN AU/m));

  const packages = {};
  const result = [];
  const re = /^(.*)@([^@]*?)$/;

  Object.entries(json).forEach(([name, pkg]) => {
    if (name.match(re)) {
      const [_, packageName, requestedVersion] = name.match(re);
      packages[packageName] = packages[packageName] || [];
      packages[packageName].push(
        Object.assign({}, { name, pkg, packageName, requestedVersion })
      );
    }
  });

  Object.entries(packages)
    .filter(([name]) => {
      if (includePackages.length === 0) return true;
      return includePackages.includes(name);
    })
    .forEach(([name, packages]) => {
      // reverse sort, so we'll find the maximum satisfying version first
      const versions = packages.map(p => p.pkg.version).sort(semver.rcompare);
      const ranges = packages.map(p => p.requestedVersion);

      // dedup each package to its maxSatisfying version
      packages.forEach(p => {
        const targetVersion = semver.maxSatisfying(
          versions,
          p.requestedVersion
        );
        if (targetVersion === null) return;
        if (targetVersion !== p.pkg.version) {
          const dedupedPackage = packages.find(
            p => p.pkg.version === targetVersion
          );
          json[`${name}@${p.requestedVersion}`] = dedupedPackage.pkg;
        }
      });
    });

  return stringify(json, noHeader, enableLockfileVersions);
};
