/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing an up-to-date package.json and a package-lock.json
 *    to be updated
 *  - name of the dependency to be updated
 *  - new dependency version
 *  - previous requirements for this dependency
 *  - the name of the lockfile (package-lock.json or npm-shrinkwrap.json)
 *
 * Outputs:
 *  - updated package.json and package-lock.json files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and package-lock.json files.
 */
import fs from "fs";
import path from "path";
import { muteStderr, runAsync } from "./helpers.js";
import { removeDependenciesFromLockfile } from "./remove-dependencies-from-lockfile.js";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const npm = require("npm");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const installer = require("npm/lib/install");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const detectIndent = require("detect-indent");

interface Dependency {
  name: string;
  version: string;
  requirements: Requirement[];
}

interface Requirement {
  source?: {
    type: string;
    url: string;
  };
  [key: string]: any;
}

export async function updateDependencyFiles(
  directory: string,
  lockfileName: string,
  dependencies: Dependency[]
): Promise<Record<string, string>> {
  const readFile = (fileName: string) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  //
  // `'prefer-offline': true` sets fetch() cache key to `force-cache`
  // https://github.com/npm/npm-registry-fetch
  //
  // `'ignore-scripts': true` used to disable prepare and prepack scripts
  // which are run when installing git dependencies
  await runAsync(npm, npm.load, [
    {
      loglevel: "silent",
      force: true,
      "prefer-offline": true,
      "ignore-scripts": true,
    },
  ]);
  const manifest = JSON.parse(readFile("package.json"));

  const dryRun = true;
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
  const initialInstaller = new installer.Installer(directory, dryRun, args, {
    packageLockOnly: true,
  });

  // A bug in npm means the initial install will remove any git dependencies
  // from the lockfile. A subsequent install with no arguments fixes this.
  const cleanupInstaller = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true,
  });

  // Skip printing the success message
  initialInstaller.printInstalled = (cb: () => void) => cb();
  cleanupInstaller.printInstalled = (cb: () => void) => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    // Fix already present git sub-dependency with invalid "from" and "requires"
    updateLockfileWithValidGitUrls(path.join(directory, lockfileName));

    await runAsync(initialInstaller, initialInstaller.run, []);

    // Fix npm5 lockfiles where invalid "from" is introduced after first install
    updateLockfileWithValidGitUrls(path.join(directory, lockfileName));

    await runAsync(cleanupInstaller, cleanupInstaller.run, []);
  } finally {
    unmute();
  }

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

function updateLockfileWithValidGitUrls(lockfilePath: string): void {
  const lockfile = fs.readFileSync(lockfilePath).toString();
  const indent = detectIndent(lockfile).indent || "  ";
  const updatedLockfileObject = removeInvalidGitUrls(JSON.parse(lockfile));
  fs.writeFileSync(
    lockfilePath,
    JSON.stringify(updatedLockfileObject, null, indent)
  );
}

function flattenAllDependencies(manifest: any): Record<string, string> {
  return Object.assign(
    {},
    manifest.optionalDependencies,
    manifest.peerDependencies,
    manifest.devDependencies,
    manifest.dependencies
  );
}

// NOTE: Reused in npm 7 updater
function installArgs(
  depName: string,
  desiredVersion: string,
  requirements: Requirement[],
  existingVersionRequirement?: string
): string {
  const source = (requirements.find((req) => req.source) || {} as any).source;

  if (source && source.type === "git") {
    if (!existingVersionRequirement) {
      existingVersionRequirement = source.url;
    }

    // Git is configured to auth over https while updating
    existingVersionRequirement = existingVersionRequirement!.replace(
      /git\+ssh:\/\/git@(.*?)[:/]/,
      "git+https://$1/"
    );

    // Keep any semver range that has already been updated in the package
    // requirement when installing the new version
    if (existingVersionRequirement!.match(desiredVersion)) {
      return `${depName}@${existingVersionRequirement}`;
    } else if (!existingVersionRequirement!.includes("#")) {
      return `${depName}@${existingVersionRequirement}`;
    } else {
      return `${depName}@${existingVersionRequirement!.replace(
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
function removeInvalidGitUrls(lockfile: any): any {
  if (!lockfile.dependencies) return lockfile;

  const dependencies = Object.keys(lockfile.dependencies).reduce<Record<string, any>>((acc, key) => {
    let value = removeInvalidGitUrlsInFrom(lockfile.dependencies[key], key);
    value = removeInvalidGitUrlsInRequires(value);
    acc[key] = removeInvalidGitUrls(value);
    return acc;
  }, {});

  return Object.assign({}, lockfile, { dependencies });
}

function removeInvalidGitUrlsInFrom(value: any, dependencyName: string): any {
  const matchKey = new RegExp(`^${dependencyName}@`);
  let from = value.from;
  if (value.from && value.from.match(matchKey)) {
    from = value.from.replace(matchKey, "");
  }

  return Object.assign({}, value, { from });
}

function removeInvalidGitUrlsInRequires(value: any): any {
  if (!value.requires) return value;

  const requires = Object.keys(value.requires).reduce<Record<string, string>>((acc, reqKey) => {
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
