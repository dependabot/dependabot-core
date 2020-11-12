const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const {
  findConflictingDependencies,
} = require("../../lib/npm/conflicting-dependency-parser");
const helpers = require("./helpers");

describe("findConflictingDependencies", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  it("finds conflicting dependencies", async () => {
    helpers.copyDependencies("conflicting-dependency-parser", tempDir);
    helpers.copyDependencies("conflicting-dependency-parser/simple", tempDir);

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        name: "objnest",
        version: "4.1.2",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("finds the top-level conflicting dependency", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/nested", tempDir);

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        name: "askconfig",
        version: "4.0.4",
        subdependency: {
          name: "objnest",
          version: "5.0.10",
          requirement: "^1.0.4",
        },
      },
    ]);
  });
});
