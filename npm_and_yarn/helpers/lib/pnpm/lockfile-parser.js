/* PNPM-LOCK.YAML PARSER
 *
 * Inputs:
 *  - directory containing a pnpm-lock.yaml file
 *
 * Outputs:
 *  - JSON formatted information of dependencies (name, version, dependency-type)
 */
const { readWantedLockfile } = require("@pnpm/lockfile-file");
const dependencyPath = require("@pnpm/dependency-path");

async function parse(directory) {
  const lockfile = await readWantedLockfile(directory, {
    ignoreIncompatible: true
  });

  return Object.entries(lockfile.packages ?? {})
    .map(([depPath, pkgSnapshot]) => nameVerDevFromPkgSnapshot(depPath, pkgSnapshot, Object.values(lockfile.importers)))
}

function nameVerDevFromPkgSnapshot(depPath, pkgSnapshot, projectSnapshots) {
  let name;
  let version;

  if (!pkgSnapshot.name) {
    const pkgInfo = dependencyPath.parse(depPath);
    name = pkgInfo.name;
    version = pkgInfo.version;
  } else {
    name = pkgSnapshot.name;
    version = pkgSnapshot.version;
  }

  let specifiers = [];
  let aliased = false;

  projectSnapshots.every(projectSnapshot => {
    const projectSpecifiers = projectSnapshot.specifiers;

    if (Object.values(projectSpecifiers).some(specifier => specifier.startsWith(`npm:${name}@`) || specifier == `npm:${name}`)) {
      aliased = true;
      return false;
    }

    currentSpecifier = projectSpecifiers[name];

    if (!currentSpecifier) {
      return true;
    }

    let specifierVersion = currentSpecifier.version;

    if (!currentSpecifier.version) {
      specifierVersion = projectSnapshot.dependencies?.[name] || projectSnapshot.devDependencies?.[name] || projectSnapshot.optionalDependencies?.[name]
    }

    if (
      specifierVersion == version ||
      specifierVersion.startsWith(`${version}_`) || // lockfileVersion 5.4
      specifierVersion.startsWith(`${version}(`)    // lockfileVersion 6.0
    ) {
      specifiers.push(currentSpecifier.specifier || currentSpecifier);
    }

    return true;
  });

  return {
    name: name,
    version: version,
    dev: pkgSnapshot.dev,
    specifiers: specifiers,
    aliased: aliased
  }
}

module.exports = { parse };
