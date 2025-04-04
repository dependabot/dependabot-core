const fs = require("fs");
const os = require("os");
const path = require("path");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const fixDuplicates = require("./fix-duplicates");
const { LightweightInstall, LOCKFILE_ENTRY_REGEX } = require("./helpers");
const { parse } = require("./lockfile-parser");
const stringify =
  require("@dependabot/yarn-lib/lib/lockfile/stringify").default;

// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(oldLockfile, newLockfile) {
  const yarnRegex = /^# yarn v(\S+)\n/gm;
  const nodeRegex = /^# node v(\S+)\n/gm;
  const oldMatch = (regex) => [].concat(oldLockfile.match(regex))[0];
  return newLockfile
    .replace(yarnRegex, () => oldMatch(yarnRegex) || "")
    .replace(nodeRegex, () => oldMatch(nodeRegex) || "");
}

async function updateDependencyFile(
  directory,
  lockfileName,
  dependencies
) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const originalYarnLock = readFile(lockfileName);

  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true,
  };
  const reporter = new EventReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: directory,
    nonInteractive: true,
    enableDefaultRc: true,
    extraneousYarnrcFiles: [".yarnrc"],
  });
  const noHeader = !Boolean(originalYarnLock.match(/^# THIS IS AN AU/m));
  config.enableLockfileVersions = Boolean(originalYarnLock.match(/^# yarn v/m));

  // SubDependencyVersionResolver relies on the install finding the latest
  // version of a sub-dependency that's been removed from the lockfile
  // YarnLockFileUpdater passes a specific version to be updated
  const lockfileObject = await parse(directory);
  for (const [entry, pkg] of Object.entries(lockfileObject)) {
    const [_, depName] = entry.match(
      LOCKFILE_ENTRY_REGEX
    );
    if (dependencies.some(dependency => dependency.name === depName)) {
      delete lockfileObject[entry];
    }
  }

  let newLockFileContent = await stringify(lockfileObject, noHeader, config.enableLockfileVersions);
  for (const dependency of dependencies) {
    newLockFileContent = fixDuplicates(newLockFileContent, dependency.name);
  }
  fs.writeFileSync(path.join(directory, lockfileName), newLockFileContent);

  const lockfile = await Lockfile.fromDirectory(directory, reporter);
  const install = new LightweightInstall(flags, config, reporter, lockfile);
  await install.init();

  const updatedYarnLock = readFile(lockfileName);
  const updatedYarnLockWithVersion = recoverVersionComments(
    originalYarnLock,
    updatedYarnLock
  );

  return {
    [lockfileName]: updatedYarnLockWithVersion,
  };
}

module.exports = { updateDependencyFile };
