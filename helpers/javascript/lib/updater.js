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
  async bailout(patterns) {
    // This is the only part of the original bailout implementation that
    // matters: saving the new lockfile
    await this.saveLockfileAndIntegrity(patterns);

    // Skip over the unnecessary steps - fetching and linking packages, etc.
    return true;
  }
}

async function allDependencyPatterns(config) {
  const manifest = await config.readRootManifest();
  return Object.assign(
    {},
    manifest.peerDependencies,
    manifest.optionalDependencies,
    manifest.devDependencies,
    manifest.dependencies
  );
}

async function updateDependencyFiles(directory, depName, desiredVersion) {
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const config = new Config(reporter);
  await config.init({ cwd: directory });

  // Find the old dependency pattern from the package.json, so we can construct
  // a new pattern that contains the new version but maintains the old format
  const currentPattern = (await allDependencyPatterns(config))[depName];
  const newPattern = currentPattern.replace(/[\d\.]*\d/, oldVersion => {
    const precision = oldVersion.split(".").length;
    return desiredVersion.split(".").slice(0, precision).join(".");
  });

  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  // Just as if we'd run `yarn add package@version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const args = [`${depName}@${newPattern}`];
  const add = new LightweightAdd(args, flags, config, reporter, lockfile);

  // Despite the innocent-sounding name, this actually does all the hard work
  await add.init();

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
