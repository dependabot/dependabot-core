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
const detectIndent = require("detect-indent");
const { formatErrorMessage } = require("./helpers");

const install = async (directory, lockfileName, dependencies) => {
  await new Promise((resolve) => {
    npm.load(resolve);
  });

  // `force` ignores checks for platform (os, cpu) and engines in
  // npm/lib/install/validate-args.js Platform is checked and raised from
  // (EBADPLATFORM): https://github.com/npm/npm-install-checks
  //
  // `ignoreScripts` is used to disable prepare and prepack scripts which are
  // run when installing git dependencies
  const arb = new Arborist({
    ...npm.flatOptions,
    path: directory,
    packageLockOnly: false,
    // NOTE: the updater sets a global .npmrc with dry-run: true to work around
    // an issue in npm 6, we don't want that here
    dryRun: false,
    ignoreScripts: true,
    // TODO: figure out if this will install invalid peer deps, we check peer
    // deps using the peer-dependency-checker but `force` is disabled, enforcing
    // platform checks in the update checker
    force: true,
    engineStrict: false,
    quiet: true,
  });

  const manifest = JSON.parse(
    fs.readFileSync(path.join(directory, "package.json")).toString()
  );
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

  await arb.reify({ add: args });

  // TODO: Do we need to do this for npm7?
  // Fix already present git sub-dependency with invalid "from" and "requires"
  updateLockfileWithValidGitUrls(path.join(directory, lockfileName));

  const updatedLockfile = fs
    .readFileSync(path.join(directory, lockfileName))
    .toString();

  return { [lockfileName]: updatedLockfile };
};

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

const updateDependencyFiles = async (directory, lockfileName, dependencies) => {
  return install(directory, lockfileName, dependencies).catch((error) => {
    throw new Error(formatErrorMessage(error));
  });
};

module.exports = { updateDependencyFiles };
