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

  const srcLockfile = path.join(
    __dirname,
    `fixtures/${sourceDir}/package-lock.json`
  );
  fs.copyFileSync(srcLockfile, `${destDir}/package-lock.json`);
};

export const copyDependenciesTree = (
  sourceDir: string,
  destDir: string
): void => {
  const srcDir = path.join(__dirname, "fixtures", sourceDir);
  fs.cpSync(srcDir, destDir, { recursive: true });
};
