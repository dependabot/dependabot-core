"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = replaceLockfileDeclaration;
const parse = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/lockfile/parse").default;
const stringify = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/lockfile/stringify").default;
// Get an array of a dependency's requested version ranges from a lockfile
function getRequestedVersions(depName, lockfileJson) {
    const requestedVersions = [];
    // Matching dependency name and version requirements which could be a full url:
    // dep@version, @private-dep@version, private-dep@https:://token@gh.com...#ref
    const re = /^(.[^@]*)@(.*?)$/;
    Object.entries(lockfileJson).forEach(([name]) => {
        if (name.match(re)) {
            const match = name.match(re);
            const [, packageName, requestedVersion] = match;
            if (packageName === depName) {
                requestedVersions.push(requestedVersion);
            }
        }
    });
    return requestedVersions;
}
function replaceLockfileDeclaration(oldLockfileContent, newLockfileContent, depName, newVersionRequirement, existingVersionRequirement) {
    const oldJson = parse(oldLockfileContent).object;
    const newJson = parse(newLockfileContent).object;
    const enableLockfileVersions = !!oldLockfileContent.match(/^# yarn v/m);
    const noHeader = !oldLockfileContent.match(/^# THIS IS AN AU/m);
    const oldPackageReqs = getRequestedVersions(depName, oldJson);
    const newPackageReqs = getRequestedVersions(depName, newJson);
    const reqToReplace = newPackageReqs.find((pattern) => {
        return !oldPackageReqs.includes(pattern);
    });
    // If the new lockfile has entries that don't exist in the old lockfile,
    // replace these version requirements with a range (will currently be an
    // exact version because we tell yarn to install a specific version)
    if (reqToReplace) {
        newJson[`${depName}@${newVersionRequirement || existingVersionRequirement}`] = newJson[`${depName}@${reqToReplace}`];
        delete newJson[`${depName}@${reqToReplace}`];
    }
    return stringify(newJson, noHeader, enableLockfileVersions);
}
//# sourceMappingURL=replace-lockfile-declaration.js.map