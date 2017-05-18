const path = require("path");
const os = require("os");
const fs = require("fs-extra");
const nock = require("nock");
const updater = require("../lib/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.removeSync(tempDir));

  it("something", async () => {
    nock("https://registry.yarnpkg.com")
      .get("/left-pad")
      .reply(200, helpers.loadFixture("yarnpkg-left-pad.json"));

    const srcPackageJson = "test/fixtures/updater/original/package.json";
    const destPackageJson = path.join(tempDir, "package.json");
    await fs.copy(srcPackageJson, destPackageJson);

    const srcYarnLock = "test/fixtures/updater/original/yarn.lock";
    const destYarnLock = path.join(tempDir, "yarn.lock");
    await fs.copy(srcYarnLock, destYarnLock);

    const name = "left-pad";
    const version = "1.1.3";
    const result = await updater.updateDependencyFiles(tempDir, name, version);

    expect(result).toEqual({
      "package.json": helpers.loadFixture("updater/updated/package.json"),
      "yarn.lock": helpers.loadFixture("updater/updated/yarn.lock")
    });
  });
});
