import path from "path";
import os from "os";
import fs from "fs";
import {
  normalizeDescriptor,
  parseNormalized,
} from "../../lib/yarn/lockfile-parser.js";
import * as helpers from "./helpers.js";

describe("normalizeDescriptor", () => {
  it("strips the npm protocol", () => {
    expect(normalizeDescriptor("abind", "npm:^1.0.0")).toEqual({
      name: "abind",
      requirement: "^1.0.0",
    });
  });

  it("resolves npm aliases", () => {
    expect(normalizeDescriptor("objnest-alias", "npm:objnest@^4.1.2")).toEqual({
      name: "objnest",
      requirement: "^4.1.2",
    });
  });

  it("resolves scoped npm aliases", () => {
    expect(
      normalizeDescriptor("objnest-alias", "npm:@scope/objnest@^4.1.2")
    ).toEqual({ name: "@scope/objnest", requirement: "^4.1.2" });
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

  it("returns dependency edges for yarn v1 lockfiles", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/simple", tempDir);

    const lockfileJson = await parseNormalized(tempDir);
    expect(Object.keys(lockfileJson).sort()).toEqual([
      "abind@^1.0.0",
      "extend@^3.0.0",
      "objnest@^4.1.2",
    ]);
    expect(lockfileJson["objnest@^4.1.2"].dependencies).toEqual([
      { name: "abind", requirement: "^1.0.0" },
      { name: "extend", requirement: "^3.0.0" },
    ]);
  });

  it("dealiases yarn v1 alias entries", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/aliased", tempDir);

    const lockfileJson = await parseNormalized(tempDir);
    expect(Object.keys(lockfileJson)).toContain("objnest@^4.1.2");
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
      "test@workspace:.",
    ]);
    expect(lockfileJson["objnest@^5.0.6"].dependencies).toEqual([
      { name: "abind", requirement: "^1.0.4" },
    ]);
  });

  it("preserves every edge when aliases resolve to the same package", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/aliased-duplicate",
      tempDir
    );

    const lockfileJson = await parseNormalized(tempDir);
    expect(lockfileJson["askconfig@^4.0.4"].dependencies).toEqual([
      { name: "abind", requirement: "^2.0.0" },
      { name: "abind", requirement: "^1.0.0" },
    ]);
  });

  it("keeps unsupported protocols verbatim so descriptors still match", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    const lockfileJson = await parseNormalized(tempDir);
    expect(Object.keys(lockfileJson).sort()).toEqual([
      "abind@^1.0.0",
      "extend@patch:extend@npm%3A3.0.2#./.yarn/patches/extend.patch",
      "local-pkg@workspace:packages/local-pkg",
      "objnest@^4.1.2",
      "test@workspace:.",
    ]);
    expect(lockfileJson["objnest@^4.1.2"].dependencies).toEqual([
      { name: "abind", requirement: "^1.0.0" },
      { name: "local-pkg", requirement: "workspace:*" },
    ]);
  });
});
