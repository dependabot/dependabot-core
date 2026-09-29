import path from "path";
import os from "os";
import fs from "fs";
import { findConflictingDependencies } from "../../lib/yarn/conflicting-dependency-parser.js";
import * as helpers from "./helpers.js";

function findNormalizedConflictingDependencies(
  directory: string,
  dependencyName: string,
  targetVersion: string
) {
  return findConflictingDependencies(
    directory,
    dependencyName,
    targetVersion,
    true
  );
}

describe("findConflictingDependencies", () => {
  let tempDir: string;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  it("finds conflicting dependencies", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/simple", tempDir);

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
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
        explanation: `apass@1.1.0 requires abind@^1.0.0 via a transitive dependency on objnest@3.0.9`,
        name: "objnest",
        version: "3.0.9",
        requirement: "^1.0.0",
      },
      {
        explanation: "apass@1.1.0 requires abind@^1.0.0 via cipherjson@2.1.0",
        name: "cipherjson",
        version: "2.1.0",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("explains conflicting devDependencies", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/dev-dependencies",
      tempDir
    );

    const result = await findConflictingDependencies(tempDir, "abind", "2.0.0");
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("finds conflicting dependencies in a yarn berry lockfile", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-simple",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("finds the top-level conflicting dependency in a yarn berry lockfile", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-nested",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "askconfig@4.0.4 requires abind@^1.0.4 via objnest@5.0.10",
        name: "objnest",
        version: "5.0.10",
        requirement: "^1.0.4",
      },
    ]);
  });

  it("resolves aliases and ignores non-npm protocols in a yarn berry lockfile", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("traverses non-registry descriptors containing commas", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-file-comma",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "local-pkg@1.0.0 requires abind@^1.0.0",
        name: "local-pkg",
        version: "1.0.0",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("does not treat a workspace requirement as a conflict", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "local-pkg",
      "2.0.0"
    );
    expect(result).toEqual([]);
  });

  it("evaluates the nested npm requirement in a patch locator", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    await expect(
      findNormalizedConflictingDependencies(tempDir, "extend", "3.0.2")
    ).resolves.toEqual([]);
    await expect(
      findNormalizedConflictingDependencies(tempDir, "extend", "4.0.0")
    ).resolves.toEqual([
      {
        explanation: "objnest@4.1.4 requires extend@3.0.2",
        name: "objnest",
        version: "4.1.4",
        requirement: "3.0.2",
      },
    ]);
  });

  it("traverses a built-in patch entry from a plain dependency edge", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-builtin-patch",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "sane@2.0.0 requires abind@^1.0.0 via fsevents@1.1.3",
        name: "fsevents",
        version: "1.1.3",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("reports an opaque locator as a conflict", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-protocols",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "opaque",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires opaque@file:../opaque",
        name: "objnest",
        version: "4.1.4",
        requirement: "file:../opaque",
      },
    ]);
  });

  it("returns no conflicts when the yarn berry lockfile allows the target version", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-simple",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "1.0.5"
    );
    expect(result).toEqual([]);
  });

  it("does not report a workspace manifest constraint as a conflict", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-simple",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "objnest",
      "5.0.0"
    );
    expect(result).toEqual([]);
  });

  it("finds conflicting dependencies behind a yarn v1 npm alias", async () => {
    helpers.copyDependencies("conflicting-dependency-parser/aliased", tempDir);

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("finds conflicting dependencies behind a versionless yarn berry alias", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-versionless-alias",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("treats versionless aliases as wildcards while preserving explicit tags", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-versionless-alias-requirement",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "objnest",
      "5.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "alias-parent@1.0.0 requires objnest@latest",
        name: "alias-parent",
        version: "1.0.0",
        requirement: "latest",
      },
    ]);
  });

  it("uses legacy yarn v1 traversal by default", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/aliased-in-key",
      tempDir
    );

    const result = await findConflictingDependencies(
      tempDir,
      "lodash",
      "5.0.0"
    );
    expect(result).toEqual([]);
  });

  it("finds conflicting dependencies behind a yarn alias declared in the dependency name", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/aliased-in-key",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "lodash",
      "5.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "fetch-factory@0.0.2 requires lodash@^4.18.1",
        name: "fetch-factory",
        version: "0.0.2",
        requirement: "^4.18.1",
      },
    ]);
  });

  it("evaluates every edge when aliases resolve to the same package", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/aliased-duplicate",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "askconfig@4.0.4 requires abind@^1.0.0",
        name: "askconfig",
        version: "4.0.4",
        requirement: "^1.0.0",
      },
      {
        explanation: "askconfig@4.0.4 requires abind@^0.1.0",
        name: "askconfig",
        version: "4.0.4",
        requirement: "^0.1.0",
      },
    ]);
  });

  it("reports the same blocker through each top-level dependency", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/multiple-top-level-ancestors",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation:
          "top-level-a@1.0.0 requires abind@^1.0.0 via shared-parent@1.0.0",
        name: "shared-parent",
        version: "1.0.0",
        requirement: "^1.0.0",
      },
      {
        explanation:
          "top-level-b@1.0.0 requires abind@^1.0.0 via shared-parent@1.0.0",
        name: "shared-parent",
        version: "1.0.0",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("traverses workspace packages not referenced by the root manifest", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-workspace",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation:
          "local-pkg@0.0.0-use.local requires abind@^1.0.0 via objnest@4.1.4",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("does not traverse a root workspace dependency twice", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/berry-referenced-workspace",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation:
          "local-pkg@0.0.0-use.local requires abind@^1.0.0 via objnest@4.1.4",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
    ]);
  });

  it("traverses every resolution when a package and its alias share a requirement", async () => {
    helpers.copyDependencies(
      "conflicting-dependency-parser/aliased-distinct",
      tempDir
    );

    const result = await findNormalizedConflictingDependencies(
      tempDir,
      "abind",
      "2.0.0"
    );
    expect(result).toEqual([
      {
        explanation: "objnest@4.1.4 requires abind@^1.0.0",
        name: "objnest",
        version: "4.1.4",
        requirement: "^1.0.0",
      },
      {
        explanation: "objnest@4.1.2 requires abind@^1.0.4",
        name: "objnest",
        version: "4.1.2",
        requirement: "^1.0.4",
      },
    ]);
  });
});
