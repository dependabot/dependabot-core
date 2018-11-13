const fs = require("fs");
const path = require("path");
const npm6 = require("npm");
const npm5 = require("npm5/node_modules/npm");
const { installerForLockfile, muteStderr, runAsync } = require("./helpers.js");

async function updateDependencyFile(directory, lockfileName) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  await runAsync(npm6, npm6.load, [{ loglevel: "silent" }]);
  await runAsync(npm5, npm5.load, [{ loglevel: "silent" }]);
  const oldLockfile = JSON.parse(readFile(lockfileName));
  const installer = installerForLockfile(oldLockfile);

  const dryRun = true;
  const initialInstaller = new installer.Installer(directory, dryRun, [], {
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

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

module.exports = { updateDependencyFile };
