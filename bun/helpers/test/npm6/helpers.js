const path = require("path");
const fs = require("fs");

module.exports = {
  loadFixture: (fixturePath) =>
    fs.readFileSync(path.join(__dirname, "fixtures", fixturePath)).toString(),

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
