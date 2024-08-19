import updater from "./updater";
import peerDependencyChecker from "./peer-dependency-checker";
import subdependencyUpdater from "./subdependency-updater";

export default {
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies,
};
