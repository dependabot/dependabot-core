/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing an up-to-date package.json and a package-lock.json
 *    to be updated
 *  - name of the dependency to be updated
 *  - new dependency version (unused)
 *  - previous requirements for this dependency (unused)
 *
 * Outputs:
 *  - updated package.json and package-lock.json files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and package-lock.json files.
 */
const fs = require("fs");
const path = require("path");
const { promisify } = require("util");
const npm = require("npm");
const npmlog = require("npmlog");
const { Installer } = require("npm/lib/install");

async function updateDependencyFiles(
  directory,
  depName,
  desiredVersion,
  requirements
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  await runAsync(npm, npm.load, [{ loglevel: "silent" }]);

  // dryRun mode prevents the actual install
  const dryRun = true;
  const args = [`${depName}@${desiredVersion}`];
  const installer = new Installer(directory, dryRun, args);

  // Skip printing the success message
  installer.printInstalled = cb => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    // Do the dry run, then save our net set of dependencies
    await runAsync(installer, installer.run, []);
    await runAsync(installer, installer.saveToDependencies, []);
  } finally {
    unmute();
  }

  const updatedLockfile = readFile("package-lock.json");

  return { "package-lock.json": updatedLockfile };
}

function runAsync(obj, method, args) {
  return new Promise((resolve, reject) => {
    const cb = (err, ...returnValues) => {
      if (err) {
        reject(err);
      } else {
        resolve(returnValues);
      }
    };
    method.apply(obj, [...args, cb]);
  });
}

function muteStderr() {
  const original = process.stderr.write;
  process.stderr.write = () => {};
  return () => {
    process.stderr.write = original;
  };
}

module.exports = { updateDependencyFiles };
