const updater = require("./updater");
const peerDependencyChecker = require("./peer-dependency-checker");
const subdependencyUpdater = require("./subdependency-updater");

module.exports = {
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies
};
