import path from "path";
import os from "os";
import fs from "fs";
import {
  isBerryLockfile,
  normalizeRequirement,
  parse,
  parseNormalized,
} from "../../lib/yarn/lockfile-parser.js";
import * as helpers from "./helpers.js";

describe("normalizeRequirement", () => {
  it("strips the npm protocol", () => {
    expect(normalizeRequirement("npm:^1.0.0")).toEqual({
      requirement: "^1.0.0",
    });
  });

  it("resolves npm aliases", () => {
    expect(normalizeRequirement("npm:objnest@^4.1.2")).toEqual({
      name: "objnest",
      requirement: "^4.1.2",
    });
  });

  it("resolves scoped npm aliases", () => {
    expect(normalizeRequirement("npm:@scope/objnest@^4.1.2")).toEqual({
      name: "@scope/objnest",
      requirement: "^4.1.2",
    });
  });

  it("keeps plain yarn v1 requirements", () => {
    expect(normalizeRequirement("^1.0.0")).toEqual({ requirement: "^1.0.0" });
  });

  it("returns null for unsupported protocols", () => {
    expect(normalizeRequirement("workspace:*")).toBeNull();
    expect(normalizeRequirement("file:../local")).toBeNull();
    expect(
      normalizeRequirement("patch:extend@npm%3A3.0.2#./extend.patch")
    ).toBeNull();
  });
});

describe("parseNormalized", () => {
  let tempDir: string;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  it("leaves yarn v1 lockfiles untouched", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/simple", tempDir);

    const lockfileJson = await parseNormalized(tempDir);
    expect(isBerryLockfile(lockfileJson)).toBe(false);
    expect(lockfileJson).toEqual(await parse(tempDir));
    expect(lockfileJson["objnest@^4.1.2"].dependencies).toEqual({
      abind: "^1.0.0",
      extend: "^3.0.0",
    });
  });

  it("splits multi-descriptor keys and strips protocols", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-nested",
      tempDir
    );

    const lockfileJson = await parseNormalized(tempDir);
    expect(Object.keys(lockfileJson).sort()).toEqual([
      "abind@^1.0.4",
      "abind@^1.0.5",
      "askconfig@^4.0.4",
      "objnest@^5.0.6",
    ]);
    expect(lockfileJson["objnest@^5.0.6"].dependencies).toEqual({
      abind: "^1.0.4",
    });
  });

  it("dealiases entries and keeps unsupported dependency protocols", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    const lockfileJson = await parseNormalized(tempDir);
    expect(Object.keys(lockfileJson).sort()).toEqual([
      "abind@^1.0.0",
      "objnest@^4.1.2",
    ]);
    expect(lockfileJson["objnest@^4.1.2"].dependencies).toEqual({
      abind: "^1.0.0",
      "local-pkg": "workspace:*",
    });
  });
});
