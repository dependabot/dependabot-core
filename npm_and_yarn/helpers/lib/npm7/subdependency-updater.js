const fs = require("fs");
const path = require("path");
const execa = require("execa");

const updateDependencyFile = async (directory, lockfileName, dependencies) => {
  const dependencyNames = dependencies.map((dep) => dep.name);

  try {
    // TODO: Enable dry-run and package-lock-only mode (currently disabled
    // because npm7/arborist does partial resolution which breaks specs
    // expection resolution to fail)

    // - `--dry-run=false` the updater sets a global .npmrc with dry-run: true to
    //   work around an issue in npm 6, we don't want that here
    // - `--force` ignores checks for platform (os, cpu) and engines
    // - `--ignore-scripts` disables prepare and prepack scripts which are run
    //   when installing git dependencies
    await execa(
      "npm",
      [
        "update",
        ...dependencyNames,
        "--force",
        "--dry-run",
        "false",
        "--ignore-scripts",
      ],
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

module.exports = { updateDependencyFile };
