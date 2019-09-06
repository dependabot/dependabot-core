const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const nock = require("nock");
const {
  updateDependencyFiles,
  updateVersionPattern
} = require("../../lib/npm/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    nock("https://registry.npmjs.org")
      .persist()
      .get("/left-pad")
      .replyWithFile(
        200,
        path.join(__dirname, "fixtures", "npm-left-pad.json"),
        {
          "Content-Type": "application/json"
        }
      );

    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  function copyDependencies(sourceDir, destDir) {
    const srcPackageJson = path.join(
      __dirname,
      `fixtures/updater/${sourceDir}/package.json`
    );
    fs.copyFileSync(srcPackageJson, `${destDir}/package.json`);

    const srcLockfile = path.join(
      __dirname,
      `fixtures/updater/${sourceDir}/package-lock.json`
    );
    fs.copyFileSync(srcLockfile, `${destDir}/package-lock.json`);
  }

  it("generates an updated package-lock.json", async () => {
    copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, "package-lock.json", [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }]
      }
    ]);
    expect(result).toEqual({
      "package-lock.json": helpers.loadFixture(
        "updater/updated/package-lock.json"
      )
    });
  });
});
