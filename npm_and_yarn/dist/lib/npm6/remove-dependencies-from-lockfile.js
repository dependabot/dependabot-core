"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.removeDependenciesFromLockfile = removeDependenciesFromLockfile;
// Recursively removes all dependencies matching on name
function removeDependenciesFromLockfile(lockfile, dependencyNames) {
    if (!lockfile.dependencies)
        return lockfile;
    const dependencies = Object.entries(lockfile.dependencies).reduce((acc, [depName, packageValue]) => {
        if (!dependencyNames.includes(depName)) {
            acc[depName] = removeDependenciesFromLockfile(packageValue, dependencyNames);
        }
        return acc;
    }, {});
    return Object.assign({}, lockfile, { dependencies });
}
//# sourceMappingURL=remove-dependencies-from-lockfile.js.map