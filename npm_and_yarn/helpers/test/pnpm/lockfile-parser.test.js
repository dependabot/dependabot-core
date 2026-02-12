import parserLib from "../../lib/pnpm";
import fs from "node:fs";
import os from "node:os";
import path, { dirname } from "node:path";
import { fileURLToPath } from "node:url";

describe("generates an updated pnpm lock for the original file", () => {

    let tempDir;
    beforeEach(() => {
        tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
    });
    afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

    function copyDependencies(sourceDir, destDir) {
      const __filename = fileURLToPath(import.meta.url);
      const __dirname = dirname(__filename);

      const srcPnpmYaml = path.join(
          __dirname,
          `fixtures/parser/${sourceDir}/pnpm-lock.yaml`
      );
      fs.copyFileSync(srcPnpmYaml, `${destDir}/pnpm-lock.yaml`);
    }

    it("that contains duplicate dependencies", async () =>{
        copyDependencies("no_lockfile_change", tempDir);
        const result = await parserLib.parseLockfile(tempDir);

        expect(result.length).toEqual(398);
    })

    it("that contains only dev dependencies but no (prod) dependencies", async () =>{
        copyDependencies("only_dev_dependencies", tempDir);
        const result = await parserLib.parseLockfile(tempDir);

        expect(result).toEqual([
            {
                name: 'etag',
                version: '1.8.0',
                resolved: undefined,
                dev: true,
                specifiers: [ '^1.0.0' ],
                aliased: false
            }
        ]);
    })

    it("that contains dependencies which locked to versions with peer disambiguation suffix", async () =>{
        copyDependencies("peer_disambiguation", tempDir);
        const result = await parserLib.parseLockfile(tempDir);

        expect(result.length).toEqual(122);
    })

    // Should have the version in the lock file.
    it("that contains dependencies with an empty version", async () =>{
        copyDependencies("empty_version", tempDir);
        const result = await parserLib.parseLockfile(tempDir);

        expect(result.length).toEqual(9);
    })

})
