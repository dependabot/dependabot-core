const parse = require("@dependabot/yarn-lib/lib/lockfile/parse").default;
const stringify = require("@dependabot/yarn-lib/lib/lockfile/stringify")
  .default;

// Get an array of a dependency's requested version ranges from a lockfile
function getRequestedVersions(depName, lockfileJson) {
  const requestedVersions = [];
  const re = /^(.*)@([^@]*?)$/;

  Object.entries(lockfileJson).forEach(([name, _]) => {
    if (name.match(re)) {
      const [_, packageName, requestedVersion] = name.match(re);
      if (packageName === depName) {
        requestedVersions.push(requestedVersion);
      }
    }
  });

  return requestedVersions;
}

module.exports = (oldLockfileContent, newLockfileContent, depName, newReq) => {
  const oldJson = parse(oldLockfileContent).object;
  const newJson = parse(newLockfileContent).object;

  const enableLockfileVersions = Boolean(
    oldLockfileContent.match(/^# yarn v/m)
  );
  const noHeader = !Boolean(oldLockfileContent.match(/^# THIS IS AN AU/m));

  const oldPackageReqs = getRequestedVersions(depName, oldJson);
  const newPackageReqs = getRequestedVersions(depName, newJson);

  const reqToReplace = newPackageReqs.find(pattern => {
    return !oldPackageReqs.includes(pattern);
  });

  if (reqToReplace) {
    newJson[`${depName}@${newReq}`] = newJson[`${depName}@${reqToReplace}`];
    delete newJson[`${depName}@${reqToReplace}`];
  }

  return stringify(newJson, noHeader, enableLockfileVersions);
};
