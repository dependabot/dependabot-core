const updater = require("../lib/updater");
const peerDependencyChecker = require("../lib/peer-dependency-checker");
const subdependencyUpdater = require("../lib/subdependency-updater");

module.exports = {
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies
};
