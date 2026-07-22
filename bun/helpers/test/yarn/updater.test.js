const path = require("path");
const os = require("os");
const fs = require("fs");
const { updateDependencyFiles } = require("../../lib/yarn/updater");
const helpers = require("./helpers");

describe("updater", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  function copyDependencies(sourceDir, destDir) {
    const srcPackageJson = path.join(
      __dirname,
      `fixtures/updater/${sourceDir}/package.json`
    );
    fs.copyFileSync(srcPackageJson, `${destDir}/package.json`);

    const srcYarnLock = path.join(
      __dirname,
      `fixtures/updater/${sourceDir}/yarn.lock`
    );
    fs.copyFileSync(srcYarnLock, `${destDir}/yarn.lock`);
  }

  it("generates an updated yarn.lock", async () => {
    copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);
    expect(result).toEqual({
      "yarn.lock": helpers.loadFixture("updater/updated/yarn.lock"),
    });
  });

  it("doesn't modify existing version comments", async () => {
    copyDependencies("with-version-comments", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);
    expect(result["yarn.lock"]).toContain("\n# yarn v0.0.0-0\n");
    expect(result["yarn.lock"]).toContain("\n# node v0.0.0\n");
  });

  it("doesn't add version comments if they're not already there", async () => {
    copyDependencies("original", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "left-pad",
        version: "1.1.3",
        requirements: [{ file: "package.json", groups: ["dependencies"] }],
      },
    ]);
    expect(result["yarn.lock"]).not.toContain("\n# yarn v");
    expect(result["yarn.lock"]).not.toContain("\n# node");
  });

  it("doesn't show an interactive prompt when resolution fails", async () => {
    copyDependencies("original", tempDir);

    expect.assertions(1);
    try {
      // Change this test if left-pad ever reaches v99.99.99
      await updateDependencyFiles(tempDir, [
        {
          name: "left-pad",
          version: "99.99.99",
          requirements: [{ file: "package.json", groups: ["dependencies"] }],
        },
      ]);
    } catch (error) {
      expect(error).not.toBeNull();
    }
  });

  it("with a package.json which contains illegal character '@' in the name", async () => {
    copyDependencies("illegal_character", tempDir);

    try {
      await updateDependencyFiles(tempDir, [
          {
            name: "@commitlint/cli",
            version: "19.3.0",
            requirements: [
              {
                requirement: "^19.3.0",
                file: "package.json",
                groups: ["devDependencies"],
                source:
                  {
                    type: "registry",
                    url: "https://registry.yarnpkg.com"
                  }
              }
            ]
          }
        ]
      );
    } catch (error) {
      expect(error).not.toBeNull();
      expect(error.message).toEqual("package.json: Name contains illegal characters")
    }
  });

  it("correctly replaces scoped git-source package with embedded credentials", async () => {
    // This test verifies the fix for LOCKFILE_ENTRY_REGEX handling scoped
    // packages with git URLs containing @ characters (credentials).
    // The key "@scope/pkg@git+https://x@github.com/y/z" has multiple @ chars,
    // and the old regex would split incorrectly, causing replaceLockfileDeclaration
    // to fail to update the entry.
    copyDependencies("scoped-git-source", tempDir);

    const result = await updateDependencyFiles(tempDir, [
      {
        name: "@scope/pkg",
        version: "2.0.0",
        requirements: [
          {
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "git+https://x@github.com/y/z",
            },
          },
        ],
      },
    ]);

    // The updated lock should have the new version
    expect(result["yarn.lock"]).toContain('version "2.0.0"');
    // And should preserve the git URL with embedded @
    expect(result["yarn.lock"]).toContain("git+https://x@github.com/y/z");
    // Verify the old version is gone
    expect(result["yarn.lock"]).not.toContain('version "1.0.0"');
  });
});
