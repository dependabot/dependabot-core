const lockfileParser = require("../lib/lockfile-parser");
const updater = require("../lib/updater");
const subdependencyUpdater = require("../lib/subdependency-updater");
const peerDependencyChecker = require("../lib/peer-dependency-checker");

module.exports = {
  parseLockfile: lockfileParser.parse,
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies
};
