const fs = require("fs");
const os = require("os");
const path = require("path");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const fixDuplicates = require("./fix-duplicates");
const { LightweightAdd, LightweightInstall } = require("./helpers");
const { parse } = require("./lockfile-parser");
const stringify = require("@dependabot/yarn-lib/lib/lockfile/stringify")
  .default;

// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(oldLockfile, newLockfile) {
  const yarnRegex = /^# yarn v(\S+)\n/gm;
  const nodeRegex = /^# node v(\S+)\n/gm;
  const oldMatch = regex => [].concat(oldLockfile.match(regex))[0];
  return newLockfile
    .replace(yarnRegex, () => oldMatch(yarnRegex) || "")
    .replace(nodeRegex, () => oldMatch(nodeRegex) || "");
}

// Installs exact version and returns lockfile entry
async function getLockfileEntryForUpdate(depName, depVersion) {
  const directory = fs.mkdtempSync(`${os.tmpdir()}${path.sep}`);
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true
  };
  const reporter = new EventReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: directory,
    nonInteractive: true,
    enableDefaultRc: true
  });

  // Empty lockfile
  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  const arg = [`${depName}@${depVersion}`];
  await new LightweightAdd(arg, flags, config, reporter, lockfile).init();

  const lockfileObject = await parse(directory);
  const noHeader = true;
  const enableLockfileVersions = false;
  return stringify(lockfileObject, noHeader, enableLockfileVersions);
}

async function updateDependencyFile(
  directory,
  lockfileName,
  updatedDependency
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const originalYarnLock = readFile(lockfileName);

  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true
  };
  const reporter = new EventReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: directory,
    nonInteractive: true,
    enableDefaultRc: true
  });
  config.enableLockfileVersions = Boolean(originalYarnLock.match(/^# yarn v/m));
  const depName = updatedDependency && updatedDependency.name;
  const depVersion = updatedDependency && updatedDependency.version;

  // SubDependencyVersionResolver relies on the install finding the latest
  // version of a sub-dependency that's been removed from the lockfile
  // YarnLockFileUpdater passes a specific version to be updated
  if (depName && depVersion) {
    const lockfileEntryForUpdate = await getLockfileEntryForUpdate(
      depName,
      depVersion
    );
    const lockfileContent = `${originalYarnLock}\n${lockfileEntryForUpdate}`;

    const dedupedYarnLock = fixDuplicates(lockfileContent, depName);
    fs.writeFileSync(path.join(directory, lockfileName), dedupedYarnLock);
  }

  const lockfile = await Lockfile.fromDirectory(directory, reporter);
  const install = new LightweightInstall(flags, config, reporter, lockfile);
  await install.init();

  const updatedYarnLock = readFile(lockfileName);
  const updatedYarnLockWithVersion = recoverVersionComments(
    originalYarnLock,
    updatedYarnLock
  );

  return {
    [lockfileName]: updatedYarnLockWithVersion
  };
}

module.exports = { updateDependencyFile };
