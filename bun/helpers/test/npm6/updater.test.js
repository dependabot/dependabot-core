const path = require("path");
const os = require("os");
const fs = require("fs");
const { updateDependencyFiles } = require("../../lib/npm6/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  it("generates an updated package-lock.json", async () => {
    helpers.copyDependencies("updater/original", tempDir);

    const result = await updateDependencyFiles(tempDir, "package-lock.json", [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);
    expect(result).toEqual({
      "package-lock.json": helpers.loadFixture(
        "updater/updated/package-lock.json"
      ),
    });
  });
});
