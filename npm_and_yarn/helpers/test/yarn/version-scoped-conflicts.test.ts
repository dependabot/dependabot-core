import path from "path";
import os from "os";
import fs from "fs";
import { findConflictingDependencies } from "../../lib/yarn/conflicting-dependency-parser.js";

const BERRY_HEADER = `__metadata:
  version: 8
  cacheKey: 10c0

`;

function entry(name: string, range: string, version: string, deps = "") {
  return `"${name}@npm:${range}":
  version: ${version}
  resolution: "${name}@npm:${version}"
${deps ? `  dependencies:\n${deps}` : ""}  languageName: node
  linkType: hard

`;
}

describe("version-scoped findConflictingDependencies", () => {
  let tempDir: string;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  function write(manifest: object, lockfile: string) {
    fs.writeFileSync(
      path.join(tempDir, "package.json"),
      JSON.stringify(manifest)
    );
    fs.writeFileSync(path.join(tempDir, "yarn.lock"), BERRY_HEADER + lockfile);
  }

  const find = (current?: string) =>
    findConflictingDependencies(tempDir, "dep", "3.0.0", true, current);

  it("ignores parents that resolve to other installed copies", async () => {
    write(
      { dependencies: { a: "^1.0.0", b: "^1.0.0" } },
      entry("a", "^1.0.0", "1.0.0", '    dep: "npm:^1.0.0"\n') +
        entry("b", "^1.0.0", "1.0.0", '    dep: "npm:^2.0.0"\n') +
        entry("dep", "^1.0.0", "1.2.0") +
        entry("dep", "^2.0.0", "2.1.0")
    );

    expect((await find()).map((c) => c.name).sort()).toEqual(["a", "b"]);
    expect((await find("1.2.0")).map((c) => c.name)).toEqual(["a"]);
    expect((await find("2.1.0")).map((c) => c.name)).toEqual(["b"]);
  });

  it("applies manifest resolutions to rewritten requests", async () => {
    write(
      {
        dependencies: { a: "^1.0.0", dep: "^1.5.0" },
        resolutions: { "dep@^1.0.0": "npm:2.0.0" },
      },
      entry("a", "^1.0.0", "1.0.0", '    dep: "npm:^1.0.0"\n') +
        entry("dep", "^1.5.0", "1.5.0") +
        entry("dep", "2.0.0", "2.0.0")
    );

    expect(await find("1.5.0")).toEqual([]);
    expect((await find("2.0.0")).map((c) => c.name)).toEqual(["a"]);
  });
});
