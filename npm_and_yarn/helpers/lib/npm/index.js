import conflictingDependencyParser from "./conflicting-dependency-parser";
import vulnerabilityAuditor from "./vulnerability-auditor";

export default {
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
  vulnerabilityAuditor:
    vulnerabilityAuditor.findVulnerableDependencies,
};
