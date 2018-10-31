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

const fs = require("fs");
const path = require("path");
const npm6 = require("npm");
const npm5 = require("npm5/node_modules/npm");
const npm6installer = require("npm/lib/install");
const npm5installer = require("npm5/node_modules/npm/lib/install");

function install_args(depName, desiredVersion, requirements, oldLockfile) {
  const source = (requirements.find(req => req.source) || {}).source;

  if (source && source.type === "git") {
    let originalVersion = ((oldLockfile["dependencies"] || {})[depName] || {})[
      "version"
    ];

    if (!originalVersion || !originalVersion.includes("#")) {
      originalVersion = `${source.url}#ref`;
    }

    originalVersion = originalVersion.replace(
      /git\+ssh:\/\/git@(.*?)[:/]/,
      "git+https://$1/"
    );
    return [`${originalVersion.replace(/#.*/, "")}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
  }
}

function runAsync(obj, method, args) {
  return new Promise((resolve, reject) => {
    const cb = (err, ...returnValues) => {
      if (err) {
        reject(err);
      } else {
        resolve(returnValues);
      }
    };
    method.apply(obj, [...args, cb]);
  });
}

function muteStderr() {
  const original = process.stderr.write;
  process.stderr.write = () => {};
  return () => {
    process.stderr.write = original;
  };
}

function installer_for_lockfile(oldLockfile) {
  const requireObjectsIncludeMatchers = Object.keys(
    oldLockfile["dependencies"] || {}
  ).some(key => {
    const requires = oldLockfile["dependencies"][key]["requires"] || {};

    return Object.keys(requires).some(key2 =>
      requires[key2].match(/^\^|~|\<|\>/)
    );
  });

  return requireObjectsIncludeMatchers ? npm6installer : npm5installer;
}

async function checkPeerDependencies(
  directory,
  depName,
  desiredVersion,
  requirements,
  topLevelDependencies,
  lockfileName
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  await runAsync(npm6, npm6.load, [{ loglevel: "silent" }]);
  await runAsync(npm5, npm5.load, [{ loglevel: "silent" }]);
  // lockfileName = "npm-shrinkwrap.json";
  const oldLockfile = lockfileName ? JSON.parse(readFile(lockfileName)) : {};
  const installer = installer_for_lockfile(oldLockfile);

  const dryRun = true;

  // Returns dep name and version for npm install, example: ["react@16.6.0"]
  let args = install_args(depName, desiredVersion, requirements, oldLockfile);

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
    .map(dep =>
      install_args(dep.name, dep.version, dep.requirements, oldLockfile)
    )
    .reduce((acc, dep) => acc.concat(dep), []);

  args = args.concat(otherDeps);

  const initial_installer = new installer.Installer(directory, dryRun, args, {
    packageLockOnly: true
  });

  // A bug in npm means the initial install will remove any git dependencies
  // from the lockfile. A subsequent install with no arguments fixes this.
  const cleanup_installer = new installer.Installer(directory, dryRun, [], {
    packageLockOnly: true
  });

  // Skip printing the success message
  initial_installer.printInstalled = cb => cb();
  cleanup_installer.printInstalled = cb => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    await runAsync(initial_installer, initial_installer.run, []);
    await runAsync(cleanup_installer, cleanup_installer.run, []);
  } finally {
    unmute();
  }

  const peerDependencyWarnings = initial_installer.idealTree.warnings
    .filter(warning => {
      return warning.code === "EPEERINVALID";
    })
    .map(warning => {
      return warning.message;
    });

  if (peerDependencyWarnings.length) {
    console.log(peerDependencyWarnings);
  }
}

module.exports = { checkPeerDependencies };
