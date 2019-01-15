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
const npm = require("npm");
const installer = require("npm/lib/install");
const { muteStderr, runAsync } = require("./helpers.js");

async function updateDependencyFiles(directory, dependencies, lockfileName) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  await runAsync(npm, npm.load, [{ loglevel: "silent", force: true }]);
  const oldPackage = JSON.parse(readFile("package.json"));

  const dryRun = true;
  const args = dependencies.map(dependency => {
    return installArgs(
      dependency.name,
      dependency.version,
      dependency.requirements,
      oldPackage
    );
  });
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

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

function flattenAllDependencies(packageJson) {
  return Object.assign(
    {},
    packageJson.optionalDependencies,
    packageJson.peerDependencies,
    packageJson.devDependencies,
    packageJson.dependencies
  );
}

function installArgs(depName, desiredVersion, requirements, oldPackage) {
  const source = (requirements.find(req => req.source) || {}).source;

  if (source && source.type === "git") {
    let originalVersion = flattenAllDependencies(oldPackage)[depName];

    if (!originalVersion) {
      originalVersion = source.url;
    }

    originalVersion = originalVersion.replace(
      /git\+ssh:\/\/git@(.*?)[:/]/,
      "git+https://$1/"
    );
    return `${originalVersion.replace(/#.*/, "")}#${desiredVersion}`;
  } else {
    return `${depName}@${desiredVersion}`;
  }
}

module.exports = { updateDependencyFiles };
