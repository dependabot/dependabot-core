/* CONFLICTING DEPENDENCY PARSER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - target dependency version
 *
 * Outputs:
 *  - An array of objects with conflicting dependencies
 */

const semver = require("semver");
const { parse } = require("./lockfile-parser");

async function findConflictingDependencies(directory, depName, targetVersion) {
  var parents = [];

  const json = await parse(directory);
  const re = /^(.*)@([^@]*?)$/;

  Object.entries(json).forEach(([pkgName, pkg]) => {
    if (pkgName.match(re) && pkg.dependencies) {
      Object.entries(pkg.dependencies).forEach(([subDepName, spec]) => {
        if (subDepName === depName && !semver.satisfies(targetVersion, spec)) {
          const [_, packageName] = pkgName.match(re);
          parents.push({
            name: packageName,
            version: pkg.version,
            requirement: spec,
          });
        }
      });
    }
  });

  return parents;
}

module.exports = { findConflictingDependencies };
