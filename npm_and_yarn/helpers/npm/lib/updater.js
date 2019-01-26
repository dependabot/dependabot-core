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

    const intermediaryLockfile = JSON.parse(readFile(lockfileName));
    const updatedIntermediaryLockfile = removeInvalidGitUrls(
      intermediaryLockfile
    );
    fs.writeFileSync(
      path.join(directory, lockfileName),
      JSON.stringify(updatedIntermediaryLockfile, null, 2)
    );

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

// Note: Fixes bugs introduced in npm 6.6.0 for the following cases:
//
// - Fails when a sub-dependency has a "from" field that includes the dependency
//   name for git dependencies (e.g. "bignumber.js@git+https://gi...)
// - Fails when updating a npm@5 lockfile with git sub-dependencies, resulting
//   in invalid "requires" that include the dependency name for git dependencies
//   (e.g. "bignumber.js": "bignumber.js@git+https://gi...)
function removeInvalidGitUrls(lockfile) {
  if (!lockfile.dependencies) return lockfile;

  const dependencies = Object.keys(lockfile.dependencies).reduce((acc, key) => {
    let value = removeInvalidGitUrlsInFrom(lockfile.dependencies[key], key);
    value = removeInvalidGitUrlsInRequires(value);
    acc[key] = removeInvalidGitUrls(value);
    return acc;
  }, {});

  return Object.assign({}, lockfile, { dependencies });
}

function removeInvalidGitUrlsInFrom(value, dependencyName) {
  const matchKey = new RegExp(`^${dependencyName}@`);
  let from = value.from;
  if (value.from && value.from.match(matchKey)) {
    from = value.from.replace(matchKey, "");
  }

  return Object.assign({}, value, { from });
}

function removeInvalidGitUrlsInRequires(value) {
  if (!value.requires) return value;

  const requires = Object.keys(value.requires).reduce((acc, reqKey) => {
    let reqValue = value.requires[reqKey];
    const requiresMatchKey = new RegExp(`^${reqKey}@`);
    if (reqValue && reqValue.match(requiresMatchKey)) {
      reqValue = reqValue.replace(requiresMatchKey, "");
    }
    acc[reqKey] = reqValue;
    return acc;
  }, {});

  return Object.assign({}, value, { requires });
}

module.exports = { updateDependencyFiles };
