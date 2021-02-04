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

module.exports = { updateDependencyFiles };
