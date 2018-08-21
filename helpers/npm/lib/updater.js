/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing an up-to-date package.json and a package-lock.json
 *    to be updated
 *  - name of the dependency to be updated
 *  - new dependency version
 *  - previous requirements for this dependency
 *
 * Outputs:
 *  - updated package.json and package-lock.json files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and package-lock.json files.
 */
const fs = require("fs");
const path = require("path");
const { promisify } = require("util");
const npm6 = require("npm");
const npm5 = require("npm5/node_modules/npm");
const npm6installer = require("npm/lib/install");
const npm5installer = require("npm5/node_modules/npm/lib/install");

async function updateDependencyFiles(
  directory,
  depName,
  desiredVersion,
  requirements
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  await runAsync(npm6, npm6.load, [{ loglevel: "silent" }]);
  await runAsync(npm5, npm5.load, [{ loglevel: "silent" }]);
  const oldLockfile = JSON.parse(readFile("package-lock.json"));
  const installer = installer_for_lockfile(oldLockfile);

  const dryRun = true;
  const args = install_args(depName, desiredVersion, requirements, oldLockfile);
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

  const updatedLockfile = readFile("package-lock.json");

  return { "package-lock.json": updatedLockfile };
}

function install_args(depName, desiredVersion, requirements, oldLockfile) {
  const source = (
    requirements.find(req => {
      return req.source;
    }) || {}
  ).source;

  if (source && source.type === "git") {
    var originalVersion = ((oldLockfile["dependencies"] || {})[depName] || {})[
      "version"
    ];
    originalVersion = originalVersion || `${source.url}#ref`;
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
  var requireObjectsIncludeMatchers = Object.keys(
    oldLockfile["dependencies"] || {}
  ).some(key => {
    var requires = oldLockfile["dependencies"][key]["requires"] || {};
    return Object.keys(requires).some(key2 => {
      if (requires[key2].match(/^\^|~|\<|\>/)) {
        return true;
      }
    });
  });

  return requireObjectsIncludeMatchers ? npm6installer : npm5installer;
}

module.exports = { updateDependencyFiles };
