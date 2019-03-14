const fs = require("fs");
const path = require("path");
const npm = require("npm");
const installer = require("npm/lib/install");

const { muteStderr, runAsync } = require("./helpers.js");

async function updateDependencyFile(directory, lockfileName) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  //
  // `'prefer-offline': true` sets fetch() cache key to `force-cache`
  // https://github.com/npm/npm-registry-fetch
  await runAsync(npm, npm.load, [
    {
      loglevel: "silent",
      force: true,
      audit: false,
      "prefer-offline": true
    }
  ]);

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
