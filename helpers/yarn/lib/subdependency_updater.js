/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *
 * Outputs:
 *  - yarn.lock files
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

async function allDependencyRanges(config) {
  const manifest = await config.readRootManifest();
  return Object.assign(
    {},
    manifest.peerDependencies,
    manifest.optionalDependencies,
    manifest.devDependencies,
    manifest.dependencies
  );
}

// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(oldLockfile, newLockfile) {
  const yarnRegex = /^# yarn v(\S+)\n/gm;
  const nodeRegex = /^# node v(\S+)\n/gm;
  const oldMatch = regex => [].concat(oldLockfile.match(regex))[0];
  return newLockfile
    .replace(yarnRegex, match => oldMatch(yarnRegex) || "")
    .replace(nodeRegex, match => oldMatch(nodeRegex) || "");
}

function devRequirement(requirements) {
  const groups = requirements.groups;
  return (
    groups.indexOf("devDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function optionalRequirement(requirements) {
  const groups = requirements.groups;
  return (
    groups.indexOf("optionalDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function install_args_with_version(depName, desiredVersion, requirements) {
  const source = requirements.source;

  if (source && source.type === "git") {
    return [`${depName}@${source.url}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
  }
}

async function updateDependencyFiles(
  directory,
  depName,
  desiredVersion,
  requirements
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  var update_run_results = { "yarn.lock": readFile("yarn.lock") };
  for (let reqs of requirements) {
    update_run_results = Object.assign(
      update_run_results,
      await updateDependencyFile(directory, depName, desiredVersion, reqs)
    );
  }
  return update_run_results;
}

async function updateDependencyFile(
  directory,
  depName,
  desiredVersion,
  requirements
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const originalYarnLock = readFile("yarn.lock");
  const originalPackageJson = readFile("package.json");

  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true,
    dev: devRequirement(requirements),
    optional: optionalRequirement(requirements)
  };
  const reporter = new EventReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: path.join(directory, path.dirname(requirements.file)),
    nonInteractive: true,
    enableDefaultRc: true
  });
  config.enableLockfileVersions = Boolean(originalYarnLock.match(/^# yarn v/m));

  const lockfile = await Lockfile.fromDirectory(directory, reporter);
  const install = new LightweightInstall(flags, config, reporter, lockfile);
  await install.init();
  var updatedYarnLock = readFile("yarn.lock");

  updatedYarnLock = recoverVersionComments(originalYarnLock, updatedYarnLock);

  return {
    "yarn.lock": updatedYarnLock
  };
}

module.exports = { updateDependencyFiles };
