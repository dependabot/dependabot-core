import conflictingDependencyParser from "./conflicting-dependency-parser";
import vulnerabilityAuditor from "./vulnerability-auditor";

module.exports = {
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
  vulnerabilityAuditor:
    vulnerabilityAuditor.findVulnerableDependencies,
};
