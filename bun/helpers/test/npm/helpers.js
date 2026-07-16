const path = require("path");
const fs = require("fs");

module.exports = {
  copyDependencies: (sourceDir, destDir) => {
    const srcPackageJson = path.join(
      __dirname,
      `fixtures/${sourceDir}/package.json`
    );
    fs.copyFileSync(srcPackageJson, `${destDir}/package.json`);

    const srcLockfile = path.join(
      __dirname,
      `fixtures/${sourceDir}/package-lock.json`
    );
    fs.copyFileSync(srcLockfile, `${destDir}/package-lock.json`);
  },
};
