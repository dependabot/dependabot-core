import { checkPeerDependencies } from "./peer-dependency-checker.js";
import { updateDependencyFile } from "./subdependency-updater.js";

export {
  updateDependencyFile as updateSubdependency,
  checkPeerDependencies,
};
