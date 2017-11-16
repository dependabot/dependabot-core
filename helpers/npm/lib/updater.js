/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a package-lock.json
 *  - dependency name
 *  - new dependency version
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
const npm = require("npm");
const npmlog = require("npmlog");
const { Installer } = require("npm/lib/install");

async function updateDependencyFiles(
  directory,
  depName,
  desiredVersion,
  workspaces
) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  // Read the original manifest, and update the dependency specification
  const manifest = JSON.parse(readFile("package.json"));
  updateVersionInManifest(manifest, depName, desiredVersion);

  // JSONify the new package.json, and write ready for npm install to pick up
  const updatedManifest = JSON.stringify(manifest, null, 2) + "\n";
  fs.writeFileSync(path.join(directory, "package.json"), updatedManifest);

  await runAsync(npm, npm.load, [{ loglevel: "silent" }]);

  // dryRun mode prevents the actual install
  const dryRun = true;
  const installer = new Installer(directory, dryRun, []);

  // Skip printing the success message
  installer.printInstalled = cb => cb();

  // There are some hard-to-prevent bits of output.
  // This is horrible, but works.
  const unmute = muteStderr();
  try {
    // Do the dry run, then save our net set of dependencies
    await runAsync(installer, installer.run, []);
    await runAsync(installer, installer.saveToDependencies, []);
  } finally {
    unmute();
  }

  const updatedLockfile = readFile("package-lock.json");

  return {
    "package.json": updatedManifest,
    "package-lock.json": updatedLockfile
  };
}

function updateVersionPattern(currentPattern, desiredVersion) {
  const versionRegex = /[0-9]+(\.[A-Za-z0-9\-_]+)*/;
  return currentPattern.replace(versionRegex, oldVersion => {
    const oldParts = oldVersion.split(".");
    const newParts = desiredVersion.split(".");
    return oldParts
      .slice(0, newParts.length)
      .map((part, i) => (part.match(/^x\b/) ? "x" : newParts[i]))
      .join(".");
  });
}

function updateVersionInManifest(manifest, depName, desiredVersion) {
  const depTypes = ["dependencies", "devDependencies", "optionalDependencies"];
  for (let depType of depTypes) {
    if ((manifest[depType] || {})[depName]) {
      manifest[depType][depName] = updateVersionPattern(
        manifest[depType][depName],
        desiredVersion
      );
      return;
    }
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

module.exports = { updateDependencyFiles, updateVersionPattern };
