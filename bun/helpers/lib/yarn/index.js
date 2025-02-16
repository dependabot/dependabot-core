const lockfileParser = require("./lockfile-parser");
const updater = require("./updater");
const subdependencyUpdater = require("./subdependency-updater");
const peerDependencyChecker = require("./peer-dependency-checker");
const conflictingDependencyParser = require("./conflicting-dependency-parser");

module.exports = {
  parseLockfile: lockfileParser.parse,
  update: updater.updateDependencyFiles,
  updateSubdependency: subdependencyUpdater.updateDependencyFile,
  checkPeerDependencies: peerDependencyChecker.checkPeerDependencies,
  findConflictingDependencies:
    conflictingDependencyParser.findConflictingDependencies,
};
