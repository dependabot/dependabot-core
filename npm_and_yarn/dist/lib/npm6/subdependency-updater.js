"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateDependencyFile = updateDependencyFile;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const detect_indent_1 = __importDefault(require("detect-indent"));
const helpers_js_1 = require("./helpers.js");
const remove_dependencies_from_lockfile_js_1 = require("./remove-dependencies-from-lockfile.js");
const npm_1 = __importDefault(require("npm"));
// eslint-disable-next-line @typescript-eslint/no-require-imports
const installer = require("npm/lib/install");
async function updateDependencyFile(directory, lockfileName, dependencies) {
    const readFile = (fileName) => fs_1.default.readFileSync(path_1.default.join(directory, fileName)).toString();
    const lockfile = readFile(lockfileName);
    const indent = (0, detect_indent_1.default)(lockfile).indent || "  ";
    const lockfileObject = JSON.parse(lockfile);
    // Remove the dependency we want to update from the lockfile and let
    // npm find the latest resolvable version and fix the lockfile
    const updatedLockfileObject = (0, remove_dependencies_from_lockfile_js_1.removeDependenciesFromLockfile)(lockfileObject, dependencies.map((dep) => dep.name));
    fs_1.default.writeFileSync(path_1.default.join(directory, lockfileName), JSON.stringify(updatedLockfileObject, null, indent));
    // `force: true` ignores checks for platform (os, cpu) and engines
    // in npm/lib/install/validate-args.js
    // Platform is checked and raised from (EBADPLATFORM):
    // https://github.com/npm/npm-install-checks
    //
    // `'prefer-offline': true` sets fetch() cache key to `force-cache`
    // https://github.com/npm/npm-registry-fetch
    //
    // `'ignore-scripts': true` used to disable prepare and prepack scripts
    // which are run when installing git dependencies
    await (0, helpers_js_1.runAsync)(npm_1.default, npm_1.default.load, [
        {
            loglevel: "silent",
            force: true,
            "prefer-offline": true,
            "ignore-scripts": true,
        },
    ]);
    const dryRun = true;
    const initialInstaller = new installer.Installer(directory, dryRun, [], {
        packageLockOnly: true,
    });
    // A bug in npm means the initial install will remove any git dependencies
    // from the lockfile. A subsequent install with no arguments fixes this.
    const cleanupInstaller = new installer.Installer(directory, dryRun, [], {
        packageLockOnly: true,
    });
    // Skip printing the success message
    initialInstaller.printInstalled = (cb) => cb();
    cleanupInstaller.printInstalled = (cb) => cb();
    // There are some hard-to-prevent bits of output.
    // This is horrible, but works.
    const unmute = (0, helpers_js_1.muteStderr)();
    try {
        await (0, helpers_js_1.runAsync)(initialInstaller, initialInstaller.run, []);
        await (0, helpers_js_1.runAsync)(cleanupInstaller, cleanupInstaller.run, []);
    }
    finally {
        unmute();
    }
    const updatedLockfile = readFile(lockfileName);
    return { [lockfileName]: updatedLockfile };
}
//# sourceMappingURL=subdependency-updater.js.map