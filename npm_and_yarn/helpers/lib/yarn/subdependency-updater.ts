import fs from "fs";
import path from "path";
import fixDuplicates from "./fix-duplicates.js";
import { LightweightInstall, LOCKFILE_ENTRY_REGEX } from "./helpers.js";
import { parse } from "./lockfile-parser.js";

const Config =
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  require("@dependabot/yarn-lib/lib/config").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const stringify =
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  require("@dependabot/yarn-lib/lib/lockfile/stringify").default;

// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(
  oldLockfile: string,
  newLockfile: string
): string {
  const yarnRegex = /^# yarn v(\S+)\n/gm;
  const nodeRegex = /^# node v(\S+)\n/gm;
  const oldMatch = (regex: RegExp) =>
    ([] as (string | undefined)[]).concat(oldLockfile.match(regex) || [])[0];
  return newLockfile
    .replace(yarnRegex, () => oldMatch(yarnRegex) || "")
    .replace(nodeRegex, () => oldMatch(nodeRegex) || "");
}

interface Dependency {
  name: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  [key: string]: any;
}

export async function updateDependencyFile(
  directory: string,
  lockfileName: string,
  dependencies: Dependency[]
): Promise<Record<string, string>> {
  const readFile = (fileName: string) =>
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
  const noHeader = !originalYarnLock.match(/^# THIS IS AN AU/m);
  config.enableLockfileVersions = !!originalYarnLock.match(/^# yarn v/m);

  // SubDependencyVersionResolver relies on the install finding the latest
  // version of a sub-dependency that's been removed from the lockfile
  // YarnLockFileUpdater passes a specific version to be updated
  const lockfileObject = await parse(directory);
  for (const [entry] of Object.entries(lockfileObject)) {
    const match = entry.match(LOCKFILE_ENTRY_REGEX);
    if (!match) continue;
    const [, depName] = match;
    if (dependencies.some((dependency) => dependency.name === depName)) {
      delete lockfileObject[entry];
    }
  }

  let newLockFileContent = await stringify(
    lockfileObject,
    noHeader,
    config.enableLockfileVersions
  );
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
