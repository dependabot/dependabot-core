import fs from "fs";
import os from "os";
import path from "path";
import { findConflictingDependencies as findYarnConflicts } from "../../lib/yarn/conflicting-dependency-parser.js";
import { findConflictingDependencies as findNpmConflicts } from "../../lib/npm/conflicting-dependency-parser.js";

const fixtureDirectory = path.join(
  __dirname,
  "fixtures/conflicting-dependency-parser/multiple-versions"
);

describe.each([
  ["Yarn Berry", "yarn.lock", true],
  ["Yarn v1 normalized", "yarn-v1.lock", true],
  ["Yarn v1 legacy", "yarn-v1.lock", false],
  ["npm", "package-lock.json", false],
] as const)("%s version-scoped conflicts", (manager, lockfile, normalized) => {
  let directory: string;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), "version-scoped-"));
    fs.copyFileSync(
      path.join(fixtureDirectory, "package.json"),
      path.join(directory, "package.json")
    );
    fs.copyFileSync(
      path.join(fixtureDirectory, lockfile),
      path.join(directory, manager === "npm" ? lockfile : "yarn.lock")
    );
  });

  afterEach(() => fs.rmSync(directory, { recursive: true }));

  function findConflicts(targetVersion: string, currentVersion?: string) {
    return manager === "npm"
      ? findNpmConflicts(
          directory,
          "brace-expansion",
          targetVersion,
          currentVersion
        )
      : findYarnConflicts(
          directory,
          "brace-expansion",
          targetVersion,
          normalized,
          currentVersion
        );
  }

  it("does not let unrelated installed versions block a compatible patch", async () => {
    expect(await findConflicts("2.1.4", "2.1.2")).toEqual([]);
  });

  it("still reports requirements on the installed version that reject the target", async () => {
    expect(await findConflicts("3.0.0", "2.1.2")).toEqual([
      {
        explanation: "current-parent@1.0.0 requires brace-expansion@^2.0.2",
        name: "current-parent",
        version: "1.0.0",
        requirement: "^2.0.2",
      },
    ]);
  });

  it("preserves unscoped checks when no installed version is supplied", async () => {
    expect(await findConflicts("2.1.4")).toHaveLength(2);
  });

  it("uses the resolved version rather than whether a range admits the current version", async () => {
    const lockfilePath = path.join(
      directory,
      manager === "npm" ? lockfile : "yarn.lock"
    );
    fs.writeFileSync(
      lockfilePath,
      fs
        .readFileSync(lockfilePath, "utf8")
        .replaceAll("^1.1.7", "^1.1.7 || ^2.0.2")
    );

    expect(await findConflicts("3.0.0", "2.1.2")).toHaveLength(1);
  });

  it("does not treat a different installed version in the same major as a blocker", async () => {
    const lockfilePath = path.join(
      directory,
      manager === "npm" ? lockfile : "yarn.lock"
    );
    fs.writeFileSync(
      lockfilePath,
      fs
        .readFileSync(lockfilePath, "utf8")
        .replaceAll("^5.0.2", "2.0.9")
        .replaceAll("5.0.2", "2.0.9")
    );

    expect(await findConflicts("2.1.4", "2.1.2")).toEqual([]);
  });

  it("keeps exact pins as genuine blockers", async () => {
    const lockfilePath = path.join(
      directory,
      manager === "npm" ? lockfile : "yarn.lock"
    );
    fs.writeFileSync(
      lockfilePath,
      fs.readFileSync(lockfilePath, "utf8").replaceAll("^2.0.2", "2.1.2")
    );

    expect(await findConflicts("2.1.4", "2.1.2")).toEqual([
      {
        explanation: "current-parent@1.0.0 requires brace-expansion@2.1.2",
        name: "current-parent",
        version: "1.0.0",
        requirement: "2.1.2",
      },
    ]);
  });
});
