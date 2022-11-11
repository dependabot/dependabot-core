import fs from "node:fs";
import path from "node:path";
import npm from "npm";
import installer from "npm/lib/install";
import detectIndent from "detect-indent";
import removeDependenciesFromLockfile from "./remove-dependencies-from-lockfile";

const { muteStderr, runAsync } from "./helpers.js";

async function updateDependencyFile(directory, lockfileName, dependencies) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  const lockfile = readFile(lockfileName);
  const indent = detectIndent(lockfile).indent || "  ";
  const lockfileObject = JSON.parse(lockfile);
  // Remove the dependency we want to update from the lockfile and let
  // npm find the latest resolvable version and fix the lockfile
  const updatedLockfileObject = removeDependenciesFromLockfile(
    lockfileObject,
    dependencies.map((dep) => dep.name)
  );
  fs.writeFileSync(
    path.join(directory, lockfileName),
    JSON.stringify(updatedLockfileObject, null, indent)
  );

  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  //
  // `'prefer-offline': true` sets fetch() cache key to `force-cache`
  // https://github.com/npm/npm-registry-fetch
  //
  // `'ignore-scripts': true` used to disable prepare and prepack scripts
  // which are run when installing git dependencies
  await runAsync(npm, npm.load, [
    {
      loglevel: "silent",
      force: true,
      audit: false,
      "prefer-offline": true,
      "ignore-scripts": true,
    },
  ]);

  const dryRun = true;
  const initialInstaller = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true,
  });

  // A bug in npm means the initial install will remove any git dependencies
  // from the lockfile. A subsequent install with no arguments fixes this.
  const cleanupInstaller = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true,
  });

  // Skip printing the success message
  initialInstaller.printInstalled = (cb) => cb();
  cleanupInstaller.printInstalled = (cb) => cb();

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
