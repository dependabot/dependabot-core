const lockfileParser = require("./lockfile-parser");
const updater = require("./updater");
const subdependencyUpdater = require("./subdependency-updater");
const peerDependencyChecker = require("./peer-dependency-checker");

module.exports = {
  "yarn:parseLockfile": lockfileParser.parse,
  "yarn:update": updater.updateDependencyFiles,
  "yarn:updateSubdependency": subdependencyUpdater.updateDependencyFile,
  "yarn:checkPeerDependencies": peerDependencyChecker.checkPeerDependencies
};
