import parse from "./lockfile-parser";
import updateDependencyFiles from "./updater";
import updateDependencyFile from "./subdependency-updater";
import checkPeerDependencies from "./peer-dependency-checker";
import findConflictingDependencies from "./conflicting-dependency-parser";

export default {
  parseLockfile: parse,
  update: updateDependencyFiles,
  updateSubdependency: updateDependencyFile,
  checkPeerDependencies,
  findConflictingDependencies,
};
