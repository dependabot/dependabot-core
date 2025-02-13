const conflictingDependencyParser = require("./conflicting-dependency-parser");
const vulnerabilityAuditor = require("./vulnerability-auditor");

module.exports = {
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
  vulnerabilityAuditor:
    vulnerabilityAuditor.findVulnerableDependencies,
};
