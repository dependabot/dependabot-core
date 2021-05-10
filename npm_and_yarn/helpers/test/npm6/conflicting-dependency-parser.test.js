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
    helpers.copyDependencies("conflicting-dependency-parser/simple", tempDir);

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.2 requires abind@^1.0.0",
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
        explanation: "askconfig@4.0.4 requires abind@^1.0.4 via objnest@5.0.10",
        name: "objnest",
        version: "5.0.10",
        requirement: "^1.0.4",
      },
    ]);
  });

  it("explains a deeply nested dependency", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/deeply-nested",
      tempDir
    );

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        explanation: "apass@1.1.0 requires abind@^1.0.0 via cipherjson@2.1.0",
        name: "cipherjson",
        version: "2.1.0",
        requirement: "^1.0.0",
      },
      {
        explanation: `apass@1.1.0 requires abind@^1.0.0 via a transitive dependency on objnest@3.0.9`,
        name: "objnest",
        version: "3.0.9",
        requirement: "^1.0.0",
      },
    ]);
  });
});
