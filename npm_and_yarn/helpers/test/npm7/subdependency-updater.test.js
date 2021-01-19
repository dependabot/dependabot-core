const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const { updateDependencyFile } = require("../../lib/npm7/subdependency-updater");
const helpers = require("./helpers");

describe("subdependency-updater", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  it("generates an updated package-lock.json", async () => {
    helpers.copyDependencies("subdependency-updater/subdependency-in-range", tempDir);

    const result = await updateDependencyFile(tempDir, "package-lock.json", [
      {
        name: "ms",
        version: "2.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);

    const lockfile = JSON.parse(result["package-lock.json"]);
    expect(lockfile.dependencies.ms.version).toEqual("2.1.3")
    expect(lockfile.packages["node_modules/ms"].version).toEqual("2.1.3")
  });

  it("does not update the dependency when the update would be out of range", async () => {
    helpers.copyDependencies("subdependency-updater/subdependency-out-of-range", tempDir);

    const result = await updateDependencyFile(tempDir, "package-lock.json", [
      {
        name: "extend",
        version: "2.0.2",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);

    const lockfile = JSON.parse(result["package-lock.json"]);
    expect(lockfile.dependencies.extend.version).toEqual("1.3.0")
  });
});
