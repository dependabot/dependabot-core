// Recursively removes all dependencies matching on name
export default function removeDependenciesFromLockfile(lockfile, dependencyNames) {
  if (!lockfile.dependencies) return lockfile;

  const dependencies = Object.entries(lockfile.dependencies).reduce(
    (acc, [depName, packageValue]) => {
      if (!dependencyNames.includes(depName)) {
        acc[depName] = removeDependenciesFromLockfile(
          packageValue,
          dependencyNames
        );
      }

      return acc;
    },
    {}
  );

  return Object.assign({}, lockfile, { dependencies });
}
