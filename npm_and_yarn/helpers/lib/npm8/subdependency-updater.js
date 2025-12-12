const fs = require("fs");
const path = require("path");
const { promisify } = require("util");
const { exec } = require("child_process");
const detectIndent = require("detect-indent");

const execAsync = promisify(exec);

/**
 * Removes all packages matching the given names from an npm8 lockfile.
 * npm8 lockfiles (lockfileVersion 2+) have a "packages" object containing all packages
 * with "node_modules/<name>" keys. We remove the package entries but keep the
 * dependency references in parent packages - npm will resolve those when it regenerates.
 */
function removeDependenciesFromLockfile(lockfile, dependencyNames) {
  if (!lockfile.packages) return lockfile;

  const packages = Object.entries(lockfile.packages).reduce(
    (acc, [packagePath, packageValue]) => {
      // Extract package name from path (e.g., "node_modules/axios" -> "axios")
      // Handle scoped packages (e.g., "node_modules/@scope/name" -> "@scope/name")
      let packageName = packagePath;
      if (packagePath.startsWith("node_modules/")) {
        packageName = packagePath.substring("node_modules/".length);
      }

      // Skip if this is a dependency we want to remove
      if (packagePath !== "" && dependencyNames.includes(packageName)) {
        return acc;
      }

      // Keep all other packages as-is
      acc[packagePath] = packageValue;

      return acc;
    },
    {}
  );

  return { ...lockfile, packages };
}

async function updateDependencyFile(directory, lockfileName, dependencies) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  const lockfilePath = path.join(directory, lockfileName);
  const lockfile = readFile(lockfileName);
  
  // Detect indentation to preserve formatting
  const indent = detectIndent(lockfile).indent || "  ";
  
  const lockfileObject = JSON.parse(lockfile);
  
  // Remove the dependencies we want to update from the lockfile
  const updatedLockfileObject = removeDependenciesFromLockfile(
    lockfileObject,
    dependencies.map((dep) => dep.name)
  );
  
  // Write the modified lockfile
  fs.writeFileSync(
    lockfilePath,
    JSON.stringify(updatedLockfileObject, null, indent)
  );

  // Run npm install to regenerate the lockfile with updated dependencies
  // Options:
  // --package-lock-only: Only update package-lock.json, don't install to node_modules
  // --ignore-scripts: Don't run prepare/prepack scripts
  // --force: Ignore checks for platform and engines
  try {
    await execAsync(
      "npm install --package-lock-only --ignore-scripts --force",
      {
        cwd: directory,
        env: {
          ...process.env,
          // Ensure npm doesn't try to update the lockfile version
          npm_config_lockfile_version: lockfileObject.lockfileVersion
            ? lockfileObject.lockfileVersion.toString()
            : undefined,
        },
      }
    );
  } catch (error) {
    // If npm install fails, restore the original lockfile
    fs.writeFileSync(lockfilePath, lockfile);
    throw error;
  }

  const updatedLockfile = readFile(lockfileName);

  return { [lockfileName]: updatedLockfile };
}

module.exports = { updateDependencyFile, removeDependenciesFromLockfile };
