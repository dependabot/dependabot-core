import path from "path";
import fs from "fs";

export const loadFixture = (fixturePath: string): string =>
  fs.readFileSync(path.join(__dirname, "fixtures", fixturePath)).toString();

export const copyDependencies = (sourceDir: string, destDir: string): void => {
  const srcPackageJson = path.join(
    __dirname,
    `fixtures/${sourceDir}/package.json`
  );
  fs.copyFileSync(srcPackageJson, `${destDir}/package.json`);

  const srcLockfile = path.join(__dirname, `fixtures/${sourceDir}/yarn.lock`);
  fs.copyFileSync(srcLockfile, `${destDir}/yarn.lock`);
};
