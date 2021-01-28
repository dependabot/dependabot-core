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
    dryRun: false,
    ignoreScripts: true,
    force: true,
    save: true,
  });

  const dependencyNames = dependencies.map((dep) => dep.name);
  await arb.buildIdealTree({ update: { names: dependencyNames } });

  await arb.reify({
    ...npm.flatOptions,
    add: [],
  });

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
