import { updateDependencyFiles } from "./updater.js";
import { checkPeerDependencies } from "./peer-dependency-checker.js";
import { updateDependencyFile } from "./subdependency-updater.js";

export {
  updateDependencyFiles as update,
  updateDependencyFile as updateSubdependency,
  checkPeerDependencies,
};
