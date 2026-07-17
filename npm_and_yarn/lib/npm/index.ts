import { findConflictingDependencies } from "./conflicting-dependency-parser.js";
import { findVulnerableDependencies } from "./vulnerability-auditor.js";

export {
  findConflictingDependencies,
  findVulnerableDependencies as vulnerabilityAuditor,
};
