const path = require("path");
const os = require("os");
const fs = require("fs");
const {
  findConflictingDependencies,
} = require("../../lib/yarn/conflicting-dependency-parser");
const helpers = require("./helpers");

describe("version-scoped conflicts", () => {
  let directory;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), "version-scoped-"));
    helpers.copyDependencies("conflicting-dependency-parser/simple", directory);
  });

  afterEach(() => fs.rmSync(directory, { recursive: true }));

  it("ignores requirements resolving to a different installed version", async () => {
    expect(
      await findConflictingDependencies(directory, "abind", "2.1.4", "2.1.2"),
    ).toEqual([]);
  });

  it("retains blockers for the installed version being updated", async () => {
    expect(
      await findConflictingDependencies(directory, "abind", "2.0.0", "1.0.5"),
    ).toHaveLength(1);
  });
});
