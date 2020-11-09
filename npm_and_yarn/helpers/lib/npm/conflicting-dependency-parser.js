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

const Arborist = require("@npmcli/arborist");
const semver = require("semver");

async function findConflictingDependencies(directory, depName, targetVersion) {
  const arb = new Arborist({
    path: directory,
  });

  var parents = [];
  await arb.loadVirtual().then((tree) => {
    for (const node of tree.inventory.query("name", depName)) {
      for (const edge of node.edgesIn) {
        if (!semver.satisfies(targetVersion, edge.spec)) {
          var parentSpec;
          for (const fromEdge of edge.from.edgesIn.values()) {
            if (fromEdge.name == edge.from.name) {
              parentSpec = fromEdge.spec;
            }
          }

          parents.push({
            name: edge.from.name,
            version: parentSpec,
            requirement: edge.spec,
          });
        }
      }
    }
  });

  return parents;
}

module.exports = { findConflictingDependencies };
