const fs = require("fs");
const path = require("path");
const npm = require("npm7");
const Arborist = require("@npmcli/arborist");
const { formatErrorMessage } = require("./helpers");

const install = async (directory, lockfileName, dependencies) => {
  await new Promise((resolve) => {
    npm.load(resolve);
  });

  const arb = new Arborist({
    ...npm.flatOptions,
    path: directory,
    packageLockOnly: false,
    // NOTE: the updater sets a global .npmrc with dry-run: true to work around
    // an issue in npm 6, we don't want that here
    dryRun: false,
    ignoreScripts: true,
    // TODO: does this force install invalid peer deps?
    force: true,
    save: true,
  });

  const dependencyNames = dependencies.map((dep) => dep.name);
  await arb.buildIdealTree({ update: { names: dependencyNames } });

  await arb.reify();

  const updatedLockfile = fs
    .readFileSync(path.join(directory, lockfileName))
    .toString();

  return { [lockfileName]: updatedLockfile };
};

const updateDependencyFile = async (directory, lockfileName, dependencies) => {
  return install(directory, lockfileName, dependencies).catch((error) => {
    throw new Error(formatErrorMessage(error));
  });
};

module.exports = { updateDependencyFile };
