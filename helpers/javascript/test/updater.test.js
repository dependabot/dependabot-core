const path = require("path");
const os = require("os");
const fs = require("fs-extra");
const nock = require("nock");
const updateDependencyFiles = require("../lib/updater").updateDependencyFiles;
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    nock("https://registry.yarnpkg.com")
      .get("/left-pad")
      .reply(200, helpers.loadFixture("yarnpkg-left-pad.json"));

    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.removeSync(tempDir));

  async function copyDependencies(sourceDir, destDir) {
    const srcPackageJson = `test/fixtures/updater/${sourceDir}/package.json`;
    await fs.copy(srcPackageJson, `${destDir}/package.json`);

    const srcYarnLock = `test/fixtures/updater/${sourceDir}/yarn.lock`;
    await fs.copy(srcYarnLock, `${destDir}/yarn.lock`);
  }

  it("generates an updated package.json and yarn.lock", async () => {
    await copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, "left-pad", "1.1.3");
    expect(result).toEqual({
      "package.json": helpers.loadFixture("updater/updated/package.json"),
      "yarn.lock": helpers.loadFixture("updater/updated/yarn.lock")
    });
  });

  it("doesn't modify existing version comments", async () => {
    await copyDependencies("with-version-comments", tempDir);

    const result = await updateDependencyFiles(tempDir, "left-pad", "1.1.3");
    expect(result["yarn.lock"]).toContain("\n# yarn v0.0.0-0\n");
    expect(result["yarn.lock"]).toContain("\n# node v0.0.0\n");
  });

  it("doesn't add version comments if they're not already there", async () => {
    await copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, "left-pad", "1.1.3");
    expect(result["yarn.lock"]).not.toContain("\n# yarn v");
    expect(result["yarn.lock"]).not.toContain("\n# node");
  });

  it("doesn't show an interactive prompt when resolution fails", async () => {
    await copyDependencies("original", tempDir);

    expect.assertions(1);
    try {
      // Change this test if left-pad ever reaches v99.99.99
      await updateDependencyFiles(tempDir, "left-pad", "99.99.99");
    } catch (error) {
      expect(error).not.toBeNull();
    }
  });

  it("correctly updates versions currently targeting prereleases", async () => {
    nock("https://registry.yarnpkg.com")
      .get("/lodash")
      .reply(200, helpers.loadFixture("yarnpkg-lodash.json"));

    await copyDependencies("original-prerelease", tempDir);

    const result = await updateDependencyFiles(tempDir, "lodash", "4.17.4");
    expect(result).toEqual({
      "package.json": helpers.loadFixture(
        "updater/updated-prerelease/package.json"
      ),
      "yarn.lock": helpers.loadFixture("updater/updated-prerelease/yarn.lock")
    });
  });
});
