/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing an up-to-date package.json and a package-lock.json to
 *    be updated
 *  - the name of the lockfile (package-lock.json or npm-shrinkwrap.json)
 *  - array of dependencies to be updated [{name, version, requirements}]
 *
 * Outputs:
 *  - updated package-lock.json
 *
 * Update the dependency to the version specified and rewrite the
 * package-lock.json files.
 */
const fs = require("fs");
const path = require("path");
const execa = require("execa");
const detectIndent = require("detect-indent");

const updateDependencyFiles = async (directory, lockfileName, dependencies) => {
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

  // TODO: Figure out if this is still needed in npm 7
  //
  // NOTE: Fix already present git sub-dependency with invalid "from" and
  // "requires"
  updateLockfileWithValidGitUrls(path.join(directory, lockfileName));

  try {
    // TODO: Enable dry-run and package-lock-only mode (currently disabled
    // because npm7/arborist does partial resolution which breaks specs
    // that expect resolution to fail)

    // - `--dry-run=false` the updater sets a global .npmrc with dry-run: true to
    //   work around an issue in npm 6, we don't want that here
    // - `--force` ignores checks for platform (os, cpu) and engines
    // - `--ignore-scripts` disables prepare and prepack scripts which are run
    //   when installing git dependencies
    await execa(
      "npm",
      ["install", ...args, "--force", "--dry-run", "false", "--ignore-scripts"],
      { cwd: directory }
    );
  } catch (e) {
    throw new Error(e.stderr);
  }

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

module.exports = { updateDependencyFiles };
