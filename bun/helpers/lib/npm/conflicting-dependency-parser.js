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
    dryRun: true,
    ignoreScripts: true,
  });

  return await arb.loadVirtual().then((tree) => {
    const parents = [];
    for (const node of tree.inventory.query("name", depName)) {
      for (const edge of node.edgesIn) {
        if (!semver.satisfies(targetVersion, edge.spec)) {
          findTopLevelEdges(edge).forEach((topLevel) => {
            explanation = buildExplanation(node, edge, topLevel);

            parents.push({
              explanation: explanation,
              name: edge.from.name,
              version: edge.from.version,
              requirement: edge.spec,
            });
          });
        }
      }
    }

    return parents;
  });
}

function buildExplanation(node, directEdge, topLevelEdge) {
  if (directEdge.from === topLevelEdge.to) {
    // The nodes parent is top-level
    return `${directEdge.from.name}@${directEdge.from.version} requires ${directEdge.to.name}@${directEdge.spec}`;
  } else if (topLevelEdge.to.edgesOut.has(directEdge.from.name)) {
    // The nodes parent is a direct dependency of the top-level dependency
    return (
      `${topLevelEdge.to.name}@${topLevelEdge.to.version} requires ${directEdge.to.name}@${directEdge.spec} ` +
      `via ${directEdge.from.name}@${directEdge.from.version}`
    );
  } else {
    // The nodes parent is a transitive dependency of the top-level dependency
    return (
      `${topLevelEdge.to.name}@${topLevelEdge.to.version} requires ${directEdge.to.name}@${directEdge.spec} ` +
      `via a transitive dependency on ${directEdge.from.name}@${directEdge.from.version}`
    );
  }
}

function findTopLevelEdges(edge, parents = []) {
  edge.from.edgesIn.forEach((parent) => {
    if (parent.from.edgesIn.size === 0) {
      if (!parents.includes(parent)) {
        parents.push(parent);
      }
    } else {
      findTopLevelEdges(parent, parents);
    }
  });

  return parents;
}

module.exports = { findConflictingDependencies };
