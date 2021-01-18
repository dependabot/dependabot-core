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
const npm = require("npm7");
const Arborist = require("@npmcli/arborist");
const process = require("process");

// const installer = require("npm6/lib/install");
const detectIndent = require("detect-indent");

async function updateDependencyFiles(directory, lockfileName, dependencies) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  await new Promise((resolve) => {
    npm.load(resolve);
  });

  const arb = new Arborist({
    ...npm.flatOptions,
    path: directory,
    packageLockOnly: true,
    dryRun: false,
    ignoreScripts: true,
    force: true,
  });

  const manifest = JSON.parse(readFile("package.json"));
  const flattenedDependencies = flattenAllDependencies(manifest);
  const args = dependencies.map((dependency) => {
    const existingVersionRequirement = flattenedDependencies[dependency.name];
    return installArgs(
      dependency.name,
      dependency.version,
      dependency.requirements,
      existingVersionRequirement
    );
  });

  await arb.reify({
    add: args,
  });

  // TODO: Do we need to do this for npm7?
  // Fix already present git sub-dependency with invalid "from" and "requires"
  updateLockfileWithValidGitUrls(path.join(directory, lockfileName));

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

function updateLockfileWithValidGitUrls(lockfilePath) {
  const lockfile = fs.readFileSync(lockfilePath).toString();
  const indent = detectIndent(lockfile).indent || "  ";
  const updatedLockfileObject = removeInvalidGitUrls(JSON.parse(lockfile));
  fs.writeFileSync(
    lockfilePath,
    JSON.stringify(updatedLockfileObject, null, indent)
  );
}

function flattenAllDependencies(manifest) {
  return Object.assign(
    {},
    manifest.optionalDependencies,
    manifest.peerDependencies,
    manifest.devDependencies,
    manifest.dependencies
  );
}

function installArgs(
  depName,
  desiredVersion,
  requirements,
  existingVersionRequirement
) {
  const source = (requirements.find((req) => req.source) || {}).source;

  if (source && source.type === "git") {
    if (!existingVersionRequirement) {
      existingVersionRequirement = source.url;
    }

    // Git is configured to auth over https while updating
    existingVersionRequirement = existingVersionRequirement.replace(
      /git\+ssh:\/\/git@(.*?)[:/]/,
      "git+https://$1/"
    );

    // Keep any semver range that has already been updated in the package
    // requirement when installing the new version
    if (existingVersionRequirement.match(desiredVersion)) {
      return `${depName}@${existingVersionRequirement}`;
    } else {
      return `${depName}@${existingVersionRequirement.replace(
        /#.*/,
        ""
      )}#${desiredVersion}`;
    }
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
