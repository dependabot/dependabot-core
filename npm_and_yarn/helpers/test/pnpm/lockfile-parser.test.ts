import { parseLockfile } from "../../lib/pnpm/index.js";
import fs from "fs";
import os from "os";
import path from "path";

describe("generates an updated pnpm lock for the original file", () => {
  let tempDir: string;
  beforeEach(() => {
    tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
  });
  afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

  function copyDependencies(sourceDir: string, destDir: string) {
    const srcPnpmYaml = path.join(
      __dirname,
      `fixtures/parser/${sourceDir}/pnpm-lock.yaml`
    );
    fs.copyFileSync(srcPnpmYaml, `${destDir}/pnpm-lock.yaml`);
  }

  it("that contains duplicate dependencies", async () => {
    copyDependencies("no_lockfile_change", tempDir);
    const result = await parseLockfile(tempDir);

    expect(result.length).toEqual(398);
  });

  it("that contains only dev dependencies but no (prod) dependencies", async () => {
    copyDependencies("only_dev_dependencies", tempDir);
    const result = await parseLockfile(tempDir);

    expect(result).toEqual([
      {
        name: "etag",
        version: "1.8.0",
        resolved: undefined,
        dev: true,
        specifiers: ["^1.0.0"],
        aliased: false,
      },
    ]);
  });

  it("that contains dependencies which locked to versions with peer disambiguation suffix", async () => {
    copyDependencies("peer_disambiguation", tempDir);
    const result = await parseLockfile(tempDir);

    expect(result.length).toEqual(122);
  });

  // Should have the version in the lock file.
  it("that contains dependencies with an empty version", async () => {
    copyDependencies("empty_version", tempDir);
    const result = await parseLockfile(tempDir);

    expect(result.length).toEqual(9);
  });

  // pnpm v9+ lockfiles don't have resolution.tarball for npm packages,
  // and GitHub tarball dependencies use a URL as the package key
  it("that uses lockfileVersion 9.0 format with a GitHub tarball dependency", async () => {
    copyDependencies("lockfile_v9_with_tarball", tempDir);
    const result = await parseLockfile(tempDir);

    expect(result).toEqual([
      {
        name: "etag",
        version: "1.8.1",
        resolved: undefined,
        dev: false,
        specifiers: ["^1.0.0"],
        aliased: false,
      },
      {
        name: "foo",
        version: "",
        resolved:
          "https://codeload.github.com/imtoo/foo/tar.gz/abc1234def5678abc1234def5678abc1234def56",
        dev: false,
        specifiers: [],
        aliased: false,
      },
    ]);
  });
});
