import { parse } from "./lockfile-parser.js";
import { updateDependencyFiles } from "./updater.js";
import { updateDependencyFile } from "./subdependency-updater.js";
import { checkPeerDependencies } from "./peer-dependency-checker.js";
import { findConflictingDependencies } from "./conflicting-dependency-parser.js";

export {
  parse as parseLockfile,
  updateDependencyFiles as update,
  updateDependencyFile as updateSubdependency,
  checkPeerDependencies,
  findConflictingDependencies,
};
