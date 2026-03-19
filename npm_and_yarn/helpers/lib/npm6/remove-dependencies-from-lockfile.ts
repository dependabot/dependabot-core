interface LockfileObject {
  dependencies?: Record<string, LockfileObject>;
  [key: string]: any;
}

// Recursively removes all dependencies matching on name
export function removeDependenciesFromLockfile(
  lockfile: LockfileObject,
  dependencyNames: string[]
): LockfileObject {
  if (!lockfile.dependencies) return lockfile;

  const dependencies = Object.entries(lockfile.dependencies).reduce<
    Record<string, LockfileObject>
  >((acc, [depName, packageValue]) => {
    if (!dependencyNames.includes(depName)) {
      acc[depName] = removeDependenciesFromLockfile(
        packageValue,
        dependencyNames
      );
    }

    return acc;
  }, {});

  return Object.assign({}, lockfile, { dependencies });
}
