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

import Arborist from "@npmcli/arborist";
import semver from "semver";

interface ConflictingDependency {
  explanation: string;
  name: string;
  version: string;
  requirement: string;
}

export async function findConflictingDependencies(
  directory: string,
  depName: string,
  targetVersion: string
): Promise<ConflictingDependency[]> {
  const arb = new Arborist({
    path: directory,
    dryRun: true,
    ignoreScripts: true,
  });

  return await arb.loadVirtual().then((tree) => {
    const parents: ConflictingDependency[] = [];
    for (const node of tree.inventory.query("name", depName)) {
      for (const edge of node.edgesIn) {
        if (!semver.satisfies(targetVersion, edge.spec)) {
          findTopLevelEdges(edge).forEach((topLevel) => {
            const explanation = buildExplanation(node, edge, topLevel);

            parents.push({
              explanation: explanation,
              name: edge.from!.name,
              version: edge.from!.version,
              requirement: edge.spec,
            });
          });
        }
      }
    }

    return parents;
  });
}

function buildExplanation(node: Arborist.Node, directEdge: Arborist.Edge, topLevelEdge: Arborist.Edge): string {
  if (directEdge.from === topLevelEdge.to) {
    // The nodes parent is top-level
    return `${directEdge.from!.name}@${directEdge.from!.version} requires ${directEdge.to!.name}@${directEdge.spec}`;
  } else if (topLevelEdge.to!.edgesOut.has(directEdge.from!.name)) {
    // The nodes parent is a direct dependency of the top-level dependency
    return (
      `${topLevelEdge.to!.name}@${topLevelEdge.to!.version} requires ${directEdge.to!.name}@${directEdge.spec} ` +
      `via ${directEdge.from!.name}@${directEdge.from!.version}`
    );
  } else {
    // The nodes parent is a transitive dependency of the top-level dependency
    return (
      `${topLevelEdge.to!.name}@${topLevelEdge.to!.version} requires ${directEdge.to!.name}@${directEdge.spec} ` +
      `via a transitive dependency on ${directEdge.from!.name}@${directEdge.from!.version}`
    );
  }
}

function findTopLevelEdges(edge: Arborist.Edge, parents: Arborist.Edge[] = []): Arborist.Edge[] {
  edge.from!.edgesIn.forEach((parent) => {
    if (parent.from!.edgesIn.size === 0) {
      if (!parents.includes(parent)) {
        parents.push(parent);
      }
    } else {
      findTopLevelEdges(parent, parents);
    }
  });

  return parents;
}
