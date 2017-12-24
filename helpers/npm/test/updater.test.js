const path = require("path");
const os = require("os");
const fs = require("fs-extra");
const nock = require("nock");
const {
  updateDependencyFiles,
  updateVersionPattern
} = require("../lib/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    nock("https://registry.npmjs.org")
      .get("/left-pad")
      .reply(200, helpers.loadFixture("npm-left-pad.json"));

    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.removeSync(tempDir));

  async function copyDependencies(sourceDir, destDir) {
    const srcPackageJson = `test/fixtures/updater/${sourceDir}/package.json`;
    await fs.copy(srcPackageJson, `${destDir}/package.json`);

    const srcLockfile = `test/fixtures/updater/${sourceDir}/package-lock.json`;
    await fs.copy(srcLockfile, `${destDir}/package-lock.json`);
  }

  it("generates an updated package-lock.json", async () => {
    await copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, "left-pad", "1.1.3");
    expect(result).toEqual({
      "package-lock.json": helpers.loadFixture(
        "updater/updated/package-lock.json"
      )
    });
  });
});
