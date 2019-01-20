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
    nock("https://registry.yarnpkg.com")
      .get("/left-pad")
      .reply(200, helpers.loadFixture("yarnpkg-left-pad.json"));
    nock("https://registry.yarnpkg.com")
      .get("/is-positive")
      .reply(200, helpers.loadFixture("yarnpkg-is-positive.json"));

    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.removeSync(tempDir));

  async function copyDependencies(sourceDir, destDir) {
    const srcPackageJson = path.join(__dirname, `fixtures/updater/${sourceDir}/package.json`);
    await fs.copy(srcPackageJson, `${destDir}/package.json`);

    const srcYarnLock = path.join(__dirname, `fixtures/updater/${sourceDir}/yarn.lock`);
    await fs.copy(srcYarnLock, `${destDir}/yarn.lock`);
  }

  it("generates an updated yarn.lock", async () => {
    await copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }]
      }
    ]);
    expect(result).toEqual({
      "yarn.lock": helpers.loadFixture("updater/updated/yarn.lock")
    });
  });

  it("doesn't modify existing version comments", async () => {
    await copyDependencies("with-version-comments", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }]
      }
    ]);
    expect(result["yarn.lock"]).toContain("\n# yarn v0.0.0-0\n");
    expect(result["yarn.lock"]).toContain("\n# node v0.0.0\n");
  });

  it("doesn't add version comments if they're not already there", async () => {
    await copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }]
      }
    ]);
    expect(result["yarn.lock"]).not.toContain("\n# yarn v");
    expect(result["yarn.lock"]).not.toContain("\n# node");
  });

  it("doesn't show an interactive prompt when resolution fails", async () => {
    await copyDependencies("original", tempDir);

    expect.assertions(1);
    try {
      // Change this test if left-pad ever reaches v99.99.99
      await updateDependencyFiles(tempDir, [
        {
          name: "left-pad",
          version: "99.99.99",
          requirements: [{ file: "package.json", groups: ["dependencies"] }]
        }
      ]);
    } catch (error) {
      expect(error).not.toBeNull();
    }
  });
});
