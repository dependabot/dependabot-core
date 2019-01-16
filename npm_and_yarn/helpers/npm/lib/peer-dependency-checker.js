/* PEER DEPENDENCY CHECKER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *  - requirements for this dependency
 *
 * Outputs:
 *  - successful completion, or an error if there are peer dependency warnings
 */

const npm = require("npm");
const installer = require("npm/lib/install");
const { muteStderr, runAsync } = require("./helpers.js");

function installArgsWithVersion(depName, desiredVersion, requirements) {
  const source = (requirements.find(req => req.source) || {}).source;

  if (source && source.type === "git") {
    return [`${depName}@${source.url}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
  }
}

async function checkPeerDependencies(
  directory,
  depName,
  desiredVersion,
  requirements,
  topLevelDependencies
) {
  // `force: true` ignores checks for platform (os, cpu) and engines
  // in npm/lib/install/validate-args.js
  // Platform is checked and raised from (EBADPLATFORM):
  // https://github.com/npm/npm-install-checks
  await runAsync(npm, npm.load, [{ loglevel: "silent", force: true }]);

  const dryRun = true;

  // Returns dep name and version for npm install, example: ["react@16.6.0"]
  let args = installArgsWithVersion(depName, desiredVersion, requirements);

  // To check peer dependencies requirements in all top level dependencies we
  // need to explicitly tell npm to fetch all manifests by specifying the
  // existing dependency name and version in npm install

  // For exampele, if we have "react@15.6.2" and "react-dom@15.6.2" installed
  // and we want to install react@16.6.0, we need get the existing version of
  // react-dom and pass this to npm install along with the new version react,
  // this way npm fetches the manifest for react-dom and determines that we
  // can't install react@16.6.0 due to the peer dependency requirement in
  // react-dom

  // If we only pass the new dep@version to npm install, e.g. "react@16.6.0" npm
  // will only fetch the manifest for react and not know that react-dom enforces
  // a peerDependency on react

  // Returns dep name and version for npm install, example: ["react-dom@15.6.2"]
  // - given react and react-dom in top level deps
  const otherDeps = (topLevelDependencies || [])
    .filter(dep => dep.name !== depName && dep.version)
    .map(dep => installArgsWithVersion(dep.name, dep.version, dep.requirements))
    .reduce((acc, dep) => acc.concat(dep), []);

  args = args.concat(otherDeps);

  const initialInstaller = new installer.Installer(directory, dryRun, args, {
    packageLockOnly: true
  });

  // A bug in npm means the initial install will remove any git dependencies
  // from the lockfile. A subsequent install with no arguments fixes this.
  const cleanupInstaller = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true
  });

  // Skip printing the success message
  initialInstaller.printInstalled = cb => cb();
  cleanupInstaller.printInstalled = cb => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    await runAsync(initialInstaller, initialInstaller.run, []);
    await runAsync(cleanupInstaller, cleanupInstaller.run, []);
  } finally {
    unmute();
  }

  const peerDependencyWarnings = initialInstaller.idealTree.warnings
    .filter(warning => warning.code === "EPEERINVALID")
    .map(warning => warning.message);

  if (peerDependencyWarnings.length) {
    throw new Error(peerDependencyWarnings.join("\n"));
  }
}

module.exports = { checkPeerDependencies };
