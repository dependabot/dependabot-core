import path, { dirname } from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

function getDirName() {
  const __filename = fileURLToPath(import.meta.url);
  return dirname(__filename);
}

export default {
  loadFixture: (fixturePath) =>
    fs.readFileSync(path.join(getDirName(), "fixtures", fixturePath)).toString(),

  copyDependencies: (sourceDir, destDir) => {
    const srcPackageJson = path.join(
      getDirName(),
      `fixtures/${sourceDir}/package.json`
    );
    fs.copyFileSync(srcPackageJson, `${destDir}/package.json`);

    const srcLockfile = path.join(
      getDirName(),
      `fixtures/${sourceDir}/package-lock.json`
    );
    fs.copyFileSync(srcLockfile, `${destDir}/package-lock.json`);
  },
};
