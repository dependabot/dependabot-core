/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *  - new requirements for this dependency
 *
 * Outputs:
 *  - updated package.json and yarn.lock files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and yarn.lock files.
 */
const fs = require("fs");
const path = require("path");
const { Add } = require("@dependabot/yarn-lib/lib/cli/commands/add");
const { Install } = require("@dependabot/yarn-lib/lib/cli/commands/install");
const {
  cleanLockfile
} = require("@dependabot/yarn-lib/lib/cli/commands/upgrade");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const fixDuplicates = require("./fix-duplicates");
const replaceDeclaration = require("./replace-lockfile-declaration");

// Add is a subclass of the Install CLI command, which is responsible for
// adding packages to a package.json and yarn.lock. Upgrading a package is
// exactly the same as adding, except the package already exists in the
// manifests.
//
// Usually, calling Add.init() would execute a series of steps: resolve, fetch,
// link, run lifecycle scripts, cleanup, then save new manifest (package.json).
// We only care about the first and last steps: resolve, then save the new
// manifest. Fotunately, overriding bailout() gives us an opportunity to skip
// over the intermediate steps in a relatively painless fashion.
class LightweightAdd extends Add {
  // This method is called by init() at the end of the resolve step, and is
  // responsible for checking if any dependnecies need to be updated locally.
  // If everything is up to date, it'll save a new lockfile and return true,
  // which causes init() to skip over the next few steps (fetching and
  // installing packages). If there are packages that need updating, it'll
  // return false, and init() will continue on to the fetching and installing
  // steps.
  //
  // Add overrides Install's implementation to always return false - meaning
  // that it will always continue to the fetch and install steps. We want to
  // do the opposite - just save the new lockfile and stop there.
  async bailout(patterns, workspaceLayout) {
    // This is the only part of the original bailout implementation that
    // matters: saving the new lockfile
    await this.saveLockfileAndIntegrity(patterns, workspaceLayout);

    // Skip over the unnecessary steps - fetching and linking packages, etc.
    return true;
  }
}

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

  // Just as if we'd run `yarn add package@version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const args = install_args_with_version(depName, desiredVersion, requirements);
  const add = new LightweightAdd(args, flags, config, reporter, lockfile);

  // Despite the innocent-sounding name, this actually does all the hard work
  await add.init();

  // Dedupe the updated lockfile, and replace the version requirement in it
  // (which will currently be an exact version, not a requirement range)
  const dedupedYarnLock = fixDuplicates(readFile("yarn.lock"), depName);
  const replacedDeclarationYarnLock = replaceDeclaration(
    originalYarnLock,
    dedupedYarnLock,
    depName,
    requirements.requirement
  );

  // Do a normal install to ensure the lockfile doesn't change when we do
  fs.writeFileSync(
    path.join(directory, "yarn.lock"),
    replacedDeclarationYarnLock
  );
  fs.writeFileSync(path.join(directory, "package.json"), originalPackageJson);
  const lockfile2 = await Lockfile.fromDirectory(directory, reporter);
  const install2 = new LightweightInstall(flags, config, reporter, lockfile2);
  await install2.init();
  var updatedYarnLock = readFile("yarn.lock");

  updatedYarnLock = recoverVersionComments(originalYarnLock, updatedYarnLock);

  return {
    "yarn.lock": updatedYarnLock
  };
}

module.exports = { updateDependencyFiles };
