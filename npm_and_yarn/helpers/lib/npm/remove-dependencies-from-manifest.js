const fs = require("fs");
const path = require("path");

const dependencyTypes = [
  "dependencies", 
  "devDependencies", 
  "peerDependencies", 
  "optionalDependencies"
];

// Removes all dependencies matching on name
function removeDependenciesFromManifest(directory, manifestName, dependencies) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();

  manifest = readFile(manifestName);
  const manifestObject = JSON.parse(manifest);

  const updatedManifestObject = dependencyTypes.map((dependencyType) => {
    if (manifestObject?.dependencyType !== undefined) {
      manifestObject.dependencyType = _removeDependenciesFromManifest(
        manifestObject[dependencyType],
        dependencies.map((dep) => dep.name)
      );
    }
  });

  fs.writeFileSync(
    path.join(directory, manifestName),
    JSON.stringify(updatedManifestObject)
  );
}


function _removeDependenciesFromManifest(manifestObject, dependenciesToRemove) {
  dependencyTypes.map((dependencyType) => {
    let dependencies = Object.entries(manifest.dependencyType).reduce(
      (acc, [depName, packageValue]) => {
        if (!dependenciesToRemove.includes(depName)) {
          acc[depName] = _removeDependenciesFromLockfile(
            packageValue,
            dependenciesToRemove
          );
        }

        return acc;
      },
      {}
    );
  });

  return Object.assign({}, manifestObject, { dependencies });
}

module.exports = removeDependenciesFromManifest;
