const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const { updateDependencyFiles } = require("../../lib/npm7/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  it("generates an updated package-lock.json", async () => {
    helpers.copyDependencies("updater/original", tempDir);

    const result = await updateDependencyFiles(tempDir, "package-lock.json", [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);
    expect(result["package-lock.json"]).toEqual(
      helpers.loadFixture("updater/updated/package-lock.json")
    );
  });
});
