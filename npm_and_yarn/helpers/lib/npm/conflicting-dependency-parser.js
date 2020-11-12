/* Conflicting dependency parser for npm
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

  return await arb.loadVirtual().then((tree) => {
    const parents = [];
    for (const node of tree.inventory.query("name", depName)) {
      for (const edge of node.edgesIn) {
        if (!semver.satisfies(targetVersion, edge.spec)) {
          findTopLevelEdges(edge).forEach((topLevel) => {
            if (topLevel.to === edge.from) {
              parents.push({
                name: edge.from.name,
                version: edge.from.version,
                requirement: edge.spec,
              });
            } else {
              parents.push({
                name: topLevel.to.name,
                version: topLevel.to.version,
                subdependency: {
                  name: edge.from.name,
                  version: edge.from.version,
                  requirement: edge.spec,
                },
              });
            }
          });
        }
      }
    }

    return parents;
  });
}

function findTopLevelEdges(edge, parents = []) {
  edge.from.edgesIn.forEach((parent) => {
    if (parent.from.edgesIn.size === 0) {
      parents.push(parent);
    } else {
      findTopLevelEdges(parent, parents);
    }
  });

  return parents;
}

module.exports = { findConflictingDependencies };
