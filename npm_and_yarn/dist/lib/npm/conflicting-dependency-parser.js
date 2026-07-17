"use strict";
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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.findConflictingDependencies = findConflictingDependencies;
const arborist_1 = __importDefault(require("@npmcli/arborist"));
const semver_1 = __importDefault(require("semver"));
async function findConflictingDependencies(directory, depName, targetVersion) {
    const arb = new arborist_1.default({
        path: directory,
        dryRun: true,
        ignoreScripts: true,
    });
    return await arb.loadVirtual().then((tree) => {
        const parents = [];
        for (const node of tree.inventory.query("name", depName)) {
            for (const edge of node.edgesIn) {
                if (!semver_1.default.satisfies(targetVersion, edge.spec)) {
                    findTopLevelEdges(edge).forEach((topLevel) => {
                        const explanation = buildExplanation(node, edge, topLevel);
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
    }
    else if (topLevelEdge.to.edgesOut.has(directEdge.from.name)) {
        // The nodes parent is a direct dependency of the top-level dependency
        return (`${topLevelEdge.to.name}@${topLevelEdge.to.version} requires ${directEdge.to.name}@${directEdge.spec} ` +
            `via ${directEdge.from.name}@${directEdge.from.version}`);
    }
    else {
        // The nodes parent is a transitive dependency of the top-level dependency
        return (`${topLevelEdge.to.name}@${topLevelEdge.to.version} requires ${directEdge.to.name}@${directEdge.spec} ` +
            `via a transitive dependency on ${directEdge.from.name}@${directEdge.from.version}`);
    }
}
function findTopLevelEdges(edge, parents = []) {
    edge.from.edgesIn.forEach((parent) => {
        if (parent.from.edgesIn.size === 0) {
            if (!parents.includes(parent)) {
                parents.push(parent);
            }
        }
        else {
            findTopLevelEdges(parent, parents);
        }
    });
    return parents;
}
//# sourceMappingURL=conflicting-dependency-parser.js.map