/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing an up-to-date package.json and a package-lock.json
 *    to be updated
 *  - name of the dependency to be updated
 *  - new dependency version
 *  - previous requirements for this dependency
 *  - the name of the lockfile (package-lock.json or npm-shrinkwrap.json)
 *
 * Outputs:
 *  - updated package.json and package-lock.json files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and package-lock.json files.
 */
const fs = require("fs");
const path = require("path");
const npm6 = require("npm");
const npm5 = require("npm5/node_modules/npm");
const { installerForLockfile, muteStderr, runAsync } = require("./helpers.js");

async function updateDependencyFiles(
  directory,
  depName,
  desiredVersion,
  requirements,
  lockfile_name
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  await runAsync(npm6, npm6.load, [{ loglevel: "silent" }]);
  await runAsync(npm5, npm5.load, [{ loglevel: "silent" }]);
  const oldLockfile = JSON.parse(readFile(lockfile_name));
  const installer = installerForLockfile(oldLockfile);

  const dryRun = true;
  const args = installArgs(depName, desiredVersion, requirements, oldLockfile);
  const initialInstaller = new installer.Installer(directory, dryRun, args, {
    packageLockOnly: true
  });
  // A bug in npm means the initial install will remove any git dependencies
  // from the lockfile. A subsequent install with no arguments fixes this.
  const cleanupInstaller = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true
  });

  // Skip printing the success message
  initialInstaller.printInstalled = cb => cb();
  cleanupInstaller.printInstalled = cb => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    await runAsync(initialInstaller, initialInstaller.run, []);
    await runAsync(cleanupInstaller, cleanupInstaller.run, []);
  } finally {
    unmute();
  }

  const updatedLockfile = readFile(lockfile_name);

  return { [lockfile_name]: updatedLockfile };
}

function installArgs(depName, desiredVersion, requirements, oldLockfile) {
  const source = (requirements.find(req => req.source) || {}).source;

  if (source && source.type === "git") {
    let originalVersion = ((oldLockfile["dependencies"] || {})[depName] || {})[
      "version"
    ];

    if (!originalVersion || !originalVersion.includes("#")) {
      originalVersion = `${source.url}#ref`;
    }

    originalVersion = originalVersion.replace(
      /git\+ssh:\/\/git@(.*?)[:/]/,
      "git+https://$1/"
    );
    return [`${originalVersion.replace(/#.*/, "")}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
  }
}

module.exports = { updateDependencyFiles };
