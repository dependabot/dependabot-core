import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import ConfigLib from "@dependabot/yarn-lib/lib/config";
import ReportersLib from "@dependabot/yarn-lib/lib/reporters";
import LockfileLib from "@dependabot/yarn-lib/lib/lockfile";
import fixDuplicates from "./fix-duplicates";
import { LightweightInstall, LOCKFILE_ENTRY_REGEX } from "./helpers";
import parse from "./lockfile-parser";
import StringifyLib from "@dependabot/yarn-lib/lib/lockfile/stringify";

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

export default async function updateDependencyFile(
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

  const reporter = new ReportersLib['EventReporter']();
  const config = new ConfigLib.default(reporter);
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

  let newLockFileContent = await StringifyLib.default(lockfileObject, noHeader, config.enableLockfileVersions);
  for (const dependency of dependencies) {
    newLockFileContent = fixDuplicates(newLockFileContent, dependency.name);
  }
  fs.writeFileSync(path.join(directory, lockfileName), newLockFileContent);

  const lockfile = await LockfileLib.default.fromDirectory(directory, reporter);
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
