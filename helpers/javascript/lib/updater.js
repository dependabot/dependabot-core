/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *
 * Outputs:
 *  - updated package.json and yarn.lock files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and yarn.lock files.
 */
const fs = require("fs");
const path = require("path");
const { Add } = require("yarn/lib/cli/commands/add");
const Config = require("yarn/lib/config").default;
const { NoopReporter } = require("yarn/lib/reporters");
const Lockfile = require("yarn/lib/lockfile/wrapper").default;

async function updateDependencyFiles(directory, depName, desiredVersion) {
  // Setup for some Yarn internals
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const config = new Config(reporter);
  await config.init({ cwd: directory });

  const lockfile = await Lockfile.fromDirectory(directory, reporter);
  // Add is a subclass of the Install CLI command, and is responsible for
  // adding packages to your package.json and yarn.lock. Upgrading a
  // package is exactly the same as adding, except the package already
  // exists in the manifests.
  const newPattern = `${depName}@^${desiredVersion}`;
  const add = new Add([newPattern], flags, config, reporter, lockfile);
  // Usually this would be set in the call to .init(), but we don't call
  // init() as it fetches and installs all the packages
  add.addedPatterns = [];

  // This is lifted from Install.init()
  const { requests, patterns } = await add.fetchRequestFromCwd();
  await add.resolver.init(add.prepareRequests(requests), false);

  const topLevelPatterns = add.preparePatterns(patterns);

  // This saves the new yarn.lock, and is defined on Install
  await add.saveLockfileAndIntegrity(topLevelPatterns);
  // This saves the new package.json, and is defined directly on Add
  await add.savePackages();

  const updatedYarnLock = fs
    .readFileSync(path.join(directory, "yarn.lock"))
    .toString();
  const updatedPackageJson = fs
    .readFileSync(path.join(directory, "package.json"))
    .toString();

  return {
    "yarn.lock": updatedYarnLock,
    "package.json": updatedPackageJson
  };
}

module.exports = { updateDependencyFiles };
