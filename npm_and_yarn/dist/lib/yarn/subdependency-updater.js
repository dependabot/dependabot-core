"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateDependencyFile = updateDependencyFile;
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const fix_duplicates_js_1 = __importDefault(require("./fix-duplicates.js"));
const helpers_js_1 = require("./helpers.js");
const lockfile_parser_js_1 = require("./lockfile-parser.js");
const Config = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/config").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const stringify = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/lockfile/stringify").default;
// Replace the version comments in the new lockfile with the ones from the old
// lockfile. If they weren't present in the old lockfile, delete them.
function recoverVersionComments(oldLockfile, newLockfile) {
    const yarnRegex = /^# yarn v(\S+)\n/gm;
    const nodeRegex = /^# node v(\S+)\n/gm;
    const oldMatch = (regex) => [].concat(oldLockfile.match(regex) || [])[0];
    return newLockfile
        .replace(yarnRegex, () => oldMatch(yarnRegex) || "")
        .replace(nodeRegex, () => oldMatch(nodeRegex) || "");
}
async function updateDependencyFile(directory, lockfileName, dependencies) {
    const readFile = (fileName) => fs_1.default.readFileSync(path_1.default.join(directory, fileName)).toString();
    const originalYarnLock = readFile(lockfileName);
    const flags = {
        ignoreScripts: true,
        ignoreWorkspaceRootCheck: true,
        ignoreEngines: true,
    };
    const reporter = new EventReporter();
    const config = new Config(reporter);
    await config.init({
        cwd: directory,
        nonInteractive: true,
        enableDefaultRc: true,
        extraneousYarnrcFiles: [".yarnrc"],
    });
    const noHeader = !originalYarnLock.match(/^# THIS IS AN AU/m);
    config.enableLockfileVersions = !!originalYarnLock.match(/^# yarn v/m);
    // SubDependencyVersionResolver relies on the install finding the latest
    // version of a sub-dependency that's been removed from the lockfile
    // YarnLockFileUpdater passes a specific version to be updated
    const lockfileObject = await (0, lockfile_parser_js_1.parse)(directory);
    for (const [entry] of Object.entries(lockfileObject)) {
        const match = entry.match(helpers_js_1.LOCKFILE_ENTRY_REGEX);
        if (!match)
            continue;
        const [, depName] = match;
        if (dependencies.some((dependency) => dependency.name === depName)) {
            delete lockfileObject[entry];
        }
    }
    let newLockFileContent = await stringify(lockfileObject, noHeader, config.enableLockfileVersions);
    for (const dependency of dependencies) {
        newLockFileContent = (0, fix_duplicates_js_1.default)(newLockFileContent, dependency.name);
    }
    fs_1.default.writeFileSync(path_1.default.join(directory, lockfileName), newLockFileContent);
    const lockfile = await Lockfile.fromDirectory(directory, reporter);
    const install = new helpers_js_1.LightweightInstall(flags, config, reporter, lockfile);
    await install.init();
    const updatedYarnLock = readFile(lockfileName);
    const updatedYarnLockWithVersion = recoverVersionComments(originalYarnLock, updatedYarnLock);
    return {
        [lockfileName]: updatedYarnLockWithVersion,
    };
}
//# sourceMappingURL=subdependency-updater.js.map