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
      helpers.loadFixture("updater/updated/package-lock.json").trim()
    );
  });

  jest.setTimeout(10000);
  it("returns an error with a git yarn reference that can't be found", async () => {
    helpers.copyDependencies("updater/git_dependency_yarn_ref", tempDir);

    await expect(updateDependencyFiles(tempDir, "package-lock.json", [
      {
        name: "fetch-factory",
        version: "0.0.2",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ])).rejects.toThrow(
      /fatal: destination path '.*' already exists and is not an empty directory/
    );
  });
});
