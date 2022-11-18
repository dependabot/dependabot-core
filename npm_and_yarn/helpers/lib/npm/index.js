const conflictingDependencyParser = require("./conflicting-dependency-parser");
const vulnerabilityAuditor = require("./vulnerability-auditor");
const removeDependenciesFromManifest = require("./remove-dependencies-from-manifest");

module.exports = {
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
  vulnerabilityAuditor:
    vulnerabilityAuditor.findVulnerableDependencies,
  removeDependenciesFromManifest:
    removeDependenciesFromManifest.removeDependenciesFromManifest,
};
