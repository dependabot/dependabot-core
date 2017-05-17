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
  async bailout(patterns) {
    // This is the only part of the original bailout implementation that
    // matters - save the new lockfile
    await this.saveLockfileAndIntegrity(patterns);

    // Skip over the unnecessary steps - fetching and linking packages, etc.
    return true;
  }
}

async function updateDependencyFiles(directory, depName, desiredVersion) {
  // Setup for Yarn internals
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const config = new Config(reporter);
  await config.init({ cwd: directory });

  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  // Just as if we'd run `yarn add package@^version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const args = [`${depName}@^${desiredVersion}`];
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
