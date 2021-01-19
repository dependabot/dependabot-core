const fs = require("fs");
const path = require("path");
const npm = require("npm7");
const Arborist = require("@npmcli/arborist");

async function updateDependencyFile(directory, lockfileName, dependencies) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

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
    save: true,
  });

  const dependencyNames = dependencies.map((dep) => dep.name);
  await arb.buildIdealTree({ update: { names: dependencyNames }});

  await arb.reify({})

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

module.exports = { updateDependencyFile };
