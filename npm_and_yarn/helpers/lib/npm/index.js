const updater = require("./updater");
const peerDependencyChecker = require("./peer-dependency-checker");
const subdependencyUpdater = require("./subdependency-updater");

module.exports = {
  "npm:update": updater.updateDependencyFiles,
  "npm:updateSubdependency": subdependencyUpdater.updateDependencyFile,
  "npm:checkPeerDependencies": peerDependencyChecker.checkPeerDependencies
};
