import path from "path";
import os from "os";
import fs from "fs";
import {
  edgeKey,
  findEntries,
  normalizeDescriptor,
  parseNormalized,
  type NormalizedLockfileEntry,
} from "../../lib/yarn/lockfile-parser.js";
import * as helpers from "./helpers.js";

describe("normalizeDescriptor", () => {
  it("strips the npm protocol", () => {
    expect(normalizeDescriptor("abind", "npm:^1.0.0")).toEqual({
      name: "abind",
      requirement: "^1.0.0",
    });
  });

  it("retains the alias descriptor while tracking the real package name", () => {
    expect(normalizeDescriptor("objnest-alias", "npm:objnest@^4.1.2")).toEqual({
      name: "objnest-alias",
      requirement: "npm:objnest@^4.1.2",
      realName: "objnest",
    });
  });

  it("resolves scoped npm aliases while preserving descriptor identity", () => {
    expect(
      normalizeDescriptor("objnest-alias", "npm:@scope/objnest@^4.1.2")
    ).toEqual({
      name: "objnest-alias",
      requirement: "npm:@scope/objnest@^4.1.2",
      realName: "@scope/objnest",
    });
  });

  it("keeps plain yarn v1 requirements", () => {
    expect(normalizeDescriptor("abind", "^1.0.0")).toEqual({
      name: "abind",
      requirement: "^1.0.0",
    });
  });

  it("keeps unsupported protocols verbatim", () => {
    expect(normalizeDescriptor("local-pkg", "workspace:*")).toEqual({
      name: "local-pkg",
      requirement: "workspace:*",
    });
    expect(
      normalizeDescriptor("extend", "patch:extend@npm%3A3.0.2#./extend.patch")
    ).toEqual({
      name: "extend",
      requirement: "patch:extend@npm%3A3.0.2#./extend.patch",
    });
  });
});

describe("parseNormalized", () => {
  let tempDir: string;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "yarn-lockfile-parser-"));
  });
  afterEach(() => fs.rmSync(tempDir, { recursive: true, force: true }));

  const parseFixture = (
    fixture: string
  ): Promise<NormalizedLockfileEntry[]> => {
    helpers.copyDependencies(
      `conflicting-dependency-parser/${fixture}`,
      tempDir
    );
    return parseNormalized(tempDir);
  };

  it("returns dependency edges for yarn v1 lockfiles", async () => {
    const lockfile = await parseFixture("simple");

    expect(lockfile.map(edgeKey).sort()).toEqual([
      "abind@^1.0.0",
      "extend@^3.0.0",
      "objnest@^4.1.2",
    ]);
    expect(
      findEntries(lockfile, { name: "objnest", requirement: "^4.1.2" })
    ).toEqual([
      {
        name: "objnest",
        requirement: "^4.1.2",
        version: "4.1.4",
        resolved: expect.any(String),
        dependencies: [
          { name: "abind", requirement: "^1.0.0" },
          { name: "extend", requirement: "^3.0.0" },
        ],
      },
    ]);
  });

  it("retains yarn v1 alias descriptor identity", async () => {
    const lockfile = await parseFixture("aliased");

    expect(lockfile.map(edgeKey)).toContain("objnest-alias@npm:objnest@^4.1.2");
  });

  it("keeps every entry when distinct descriptors normalize to the same edge", async () => {
    const lockfile = await parseFixture("aliased-distinct");

    const plainEntries = findEntries(lockfile, {
      name: "objnest",
      requirement: "^4.1.2",
    });
    expect(plainEntries.map((entry) => entry.version).sort()).toEqual([
      "4.1.4",
    ]);

    const aliasEntries = findEntries(lockfile, {
      name: "objnest-alias",
      requirement: "npm:objnest@^4.1.2",
    });
    expect(aliasEntries.map((entry) => entry.version)).toEqual(["4.1.2"]);
  });

  it("splits multi-descriptor keys and strips protocols", async () => {
    const lockfile = await parseFixture("berry-nested");

    expect(lockfile.map(edgeKey).sort()).toEqual([
      "abind@^1.0.4",
      "abind@^1.0.5",
      "askconfig@^4.0.4",
      "objnest@^5.0.6",
      "test@workspace:.",
    ]);
    expect(
      findEntries(lockfile, { name: "objnest", requirement: "^5.0.6" })[0]
        .dependencies
    ).toEqual([{ name: "abind", requirement: "^1.0.4" }]);
  });

  it("preserves every edge when aliases resolve to the same package", async () => {
    const lockfile = await parseFixture("aliased-duplicate");

    expect(
      findEntries(lockfile, { name: "askconfig", requirement: "^4.0.4" })[0]
        .dependencies
    ).toEqual([
      {
        name: "abind-v1",
        requirement: "npm:abind@^1.0.0",
        realName: "abind",
      },
      {
        name: "abind-v0",
        requirement: "npm:abind@^0.1.0",
        realName: "abind",
      },
    ]);
  });

  it("resolves workspace ranges to their workspace entry", async () => {
    const lockfile = await parseFixture("berry-workspace");

    const entries = findEntries(lockfile, {
      name: "local-pkg",
      requirement: "workspace:*",
    });
    expect(entries).toHaveLength(1);
    expect(entries[0].requirement).toBe("workspace:packages/local-pkg");
    expect(entries[0].dependencies).toEqual([
      { name: "objnest", requirement: "^4.1.2" },
    ]);
  });

  it("keeps other protocols verbatim", async () => {
    const lockfile = await parseFixture("berry-protocols");

    expect(lockfile.map(edgeKey).sort()).toEqual([
      "abind@^1.0.0",
      "extend@patch:extend@npm%3A3.0.2#./.yarn/patches/extend.patch",
      "local-pkg@workspace:packages/local-pkg",
      "my-objnest@npm:objnest@^4.1.2",
      "test@workspace:.",
    ]);
    expect(
      findEntries(lockfile, {
        name: "my-objnest",
        requirement: "npm:objnest@^4.1.2",
      })[0].dependencies
    ).toEqual([
      { name: "abind", requirement: "^1.0.0" },
      {
        name: "extend",
        requirement: "patch:extend@npm%3A3.0.2#./.yarn/patches/extend.patch",
      },
      { name: "local-pkg", requirement: "workspace:*" },
    ]);
  });
});
