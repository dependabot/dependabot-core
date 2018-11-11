/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *
 * Outputs:
 *  - yarn.lock file
 *
 * Update the sub-dependency versions for this dependency to that latest
 * possible versions, without unlocking any other dependencies
 */
const fs = require("fs");
const path = require("path");
const { Install } = require("@dependabot/yarn-lib/lib/cli/commands/install");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;

class LightweightInstall extends Install {
  async bailout(patterns, workspaceLayout) {
    await this.saveLockfileAndIntegrity(patterns, workspaceLayout);
    return true;
  }
}

// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(oldLockfile, newLockfile) {
  const yarnRegex = /^# yarn v(\S+)\n/gm;
  const nodeRegex = /^# node v(\S+)\n/gm;
  const oldMatch = regex => [].concat(oldLockfile.match(regex))[0];
  return newLockfile
    .replace(yarnRegex, () => oldMatch(yarnRegex) || "")
    .replace(nodeRegex, () => oldMatch(nodeRegex) || "");
}

async function updateDependencyFile(directory, lockfileName) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const originalYarnLock = readFile(lockfileName);

  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true
  };
  const reporter = new EventReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: directory,
    nonInteractive: true,
    enableDefaultRc: true
  });
  config.enableLockfileVersions = Boolean(originalYarnLock.match(/^# yarn v/m));

  const lockfile = await Lockfile.fromDirectory(directory, reporter);
  const install = new LightweightInstall(flags, config, reporter, lockfile);
  await install.init();
  var updatedYarnLock = readFile(lockfileName);

  updatedYarnLock = recoverVersionComments(originalYarnLock, updatedYarnLock);

  return {
    [lockfileName]: updatedYarnLock
  };
}

module.exports = { updateDependencyFile };
