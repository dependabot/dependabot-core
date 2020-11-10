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

  Object.entries(json).forEach(([pkgName, pkg]) => {
    if (pkg.dependencies) {
      Object.entries(pkg.dependencies).forEach(([subDepName, spec]) => {
        if (subDepName === depName && !semver.satisfies(targetVersion, spec)) {
          parents.push({
            name: pkgName,
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
