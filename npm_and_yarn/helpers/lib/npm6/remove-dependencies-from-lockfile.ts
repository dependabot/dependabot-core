// Represents an entry in an npm v1 package-lock.json file.
export interface LockDependency {
  dependencies?: Record<string, LockDependency>;
  [key: string]: unknown;
}

// Recursively removes all dependencies matching on name
export function removeDependenciesFromLockfile(
  lockfile: LockDependency,
  dependencyNames: string[]
): LockDependency {
  if (!lockfile.dependencies) return lockfile;

  const dependencies = Object.entries(lockfile.dependencies).reduce<
    Record<string, LockDependency>
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
