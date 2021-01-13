const updater = require("./updater");
const peerDependencyChecker = require("./peer-dependency-checker");
const subdependencyUpdater = require("./subdependency-updater");
const conflictingDependencyParser = require("./conflicting-dependency-parser");

module.exports = {
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies,
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
};
