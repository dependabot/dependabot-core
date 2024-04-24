const {
    parseLockfile,
} = require("../../lib/pnpm");
const fs = require("fs");
const os = require("os");
const path = require("path");

describe("parseLockfile", () => {

    let tempDir;
    beforeEach(() => {
        tempDir = fs.mkdtempSync(os.tmpdir() + path.sep);
    });
    afterEach(() => fs.rm(tempDir, { recursive: true }, () => {}));

    function copyDependencies(sourceDir, destDir) {
        const srcPnpmYaml = path.join(
            __dirname,
            `fixtures/parser/${sourceDir}/pnpm-lock.yaml`
        );
        fs.copyFileSync(srcPnpmYaml, `${destDir}/pnpm-lock.yaml`);
    }

    it("no lock file change", async () =>{
        copyDependencies("no_lockfile_change", tempDir);
        const result = await parseLockfile(tempDir);

        expect(result.length).toEqual(400);
    })

    it("only dev dependency", async () =>{
        copyDependencies("only_dev_dependencies", tempDir);
        const result = await parseLockfile(tempDir);

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

    it("peer disambiguation", async () =>{
        copyDependencies("peer_disambiguation", tempDir);
        const result = await parseLockfile(tempDir);

        expect(result.length).toEqual(122);
    })

    it("empty version", async () =>{
        copyDependencies("empty_version", tempDir);
        const result = await parseLockfile(tempDir);

        expect(result.length).toEqual(9);
    })

})
