const path = require("path");
const os = require("os");
const fs = require("fs");
const rimraf = require("rimraf");
const {
  checkPeerDependencies,
} = require("../../lib/npm7/peer-dependency-checker");
const helpers = require("./helpers");

describe("checkPeerDependencies", () => {
  let tempDir;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => rimraf.sync(tempDir));

  it("updating a dependency with a peer requirement", async () => {
    helpers.copyDependencies(
      "peer-dependency-checker/peer_dependency",
      tempDir
    );

    await expect(
      checkPeerDependencies(tempDir, "react-dom", "16.14.0", [
        {
          file: "package.json",
          requirement: "16.14.0",
          groups: ["dependencies"],
          source: null,
        },
      ])
    ).rejects.toThrow(
      "react-dom@16.14.0 requires a peer of react@^16.14.0 but none is installed."
    );
  });

  it("updating a dependency that is a peer requirement", async () => {
    helpers.copyDependencies(
      "peer-dependency-checker/peer_dependency",
      tempDir
    );

    await expect(
      checkPeerDependencies(tempDir, "react", "16.14.0", [
        {
          file: "package.json",
          requirement: "16.14.0",
          groups: ["dependencies"],
          source: null,
        },
      ])
    ).rejects.toThrow(
      "react-dom@15.2.0 requires a peer of react@^15.2.0 but none is installed."
    );
  });

  it("updating a dependency that is a peer requirement of multiple dependencies", async () => {
    helpers.copyDependencies(
      "peer-dependency-checker/peer_dependency_multiple",
      tempDir
    );

    await expect(
      checkPeerDependencies(
        tempDir,
        "react",
        "0.14.2",
        [
          {
            file: "package.json",
            requirement: "0.14.2",
            groups: ["dependencies"],
            source: null,
          },
        ],
        [
          {
            name: "react",
            version: "15.2.0",
            requirements: [
              {
                file: "package.json",
                requirement: "15.2.0",
                groups: ["dependencies"],
                source: null,
              },
            ],
          },
          {
            name: "react-dom",
            version: "15.2.0",
            requirements: [
              {
                file: "package.json",
                requirement: "15.2.0",
                groups: ["dependencies"],
                source: null,
              },
            ],
          },
        ]
      )
    ).rejects.toThrow(
      "react-tabs@1.1.0 requires a peer of react@^0.14.9 || ^15.3.0 but none is installed."
    );
  });
});
