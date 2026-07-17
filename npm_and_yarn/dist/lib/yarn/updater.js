"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateDependencyFiles = updateDependencyFiles;
/* DEPENDENCY FILE UPDATER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *  - new requirements for this dependency
 *
 * Outputs:
 *  - updated package.json and yarn.lock files
 *
 * Update the dependency to the version specified and rewrite the package.json
 * and yarn.lock files.
 */
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const fix_duplicates_js_1 = __importDefault(require("./fix-duplicates.js"));
const replace_lockfile_declaration_js_1 = __importDefault(require("./replace-lockfile-declaration.js"));
const helpers_js_1 = require("./helpers.js");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Config = require("@dependabot/yarn-lib/lib/config").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
function flattenAllDependencies(manifest) {
    return Object.assign({}, manifest.optionalDependencies, manifest.peerDependencies, manifest.devDependencies, manifest.dependencies);
}
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
function devRequirement(requirements) {
    const groups = requirements.groups;
    return (groups.indexOf("devDependencies") > -1 &&
        groups.indexOf("dependencies") == -1);
}
function optionalRequirement(requirements) {
    const groups = requirements.groups;
    return (groups.indexOf("optionalDependencies") > -1 &&
        groups.indexOf("dependencies") == -1);
}
function installArgsWithVersion(depName, desiredVersion, requirements, existingVersionRequirement) {
    const source = requirements.source;
    if (source && source.type === "git") {
        if (!existingVersionRequirement) {
            existingVersionRequirement = source.url;
        }
        // Git is configured to auth over https while updating
        existingVersionRequirement = existingVersionRequirement.replace(/git\+ssh:\/\/git@(.*?)[:/]/, "git+https://$1/");
        // Keep any semver range that has already been updated in the package
        // requirement when installing the new version
        if (existingVersionRequirement.match(desiredVersion)) {
            return [`${depName}@${existingVersionRequirement}`];
        }
        else {
            return [
                `${depName}@${existingVersionRequirement.replace(/#.*/, "")}#${desiredVersion}`,
            ];
        }
    }
    else {
        return [`${depName}@${desiredVersion}`];
    }
}
async function updateDependencyFiles(directory, dependencies) {
    const readFile = (fileName) => fs_1.default.readFileSync(path_1.default.join(directory, fileName)).toString();
    let updateRunResults = {
        "yarn.lock": readFile("yarn.lock"),
    };
    const requiredVersions = [];
    for (const dep of dependencies) {
        for (const reqs of dep.requirements) {
            if (requiredVersions.indexOf(reqs.requirement) > -1) {
                continue;
            }
            updateRunResults = Object.assign(updateRunResults, await updateDependencyFile(directory, dep.name, dep.version, reqs));
            requiredVersions.push(reqs.requirement);
        }
    }
    return updateRunResults;
}
async function updateDependencyFile(directory, depName, desiredVersion, requirements) {
    const readFile = (fileName) => fs_1.default.readFileSync(path_1.default.join(directory, fileName)).toString();
    const originalYarnLock = readFile("yarn.lock");
    const originalPackageJson = readFile(requirements.file);
    const flags = {
        ignoreScripts: true,
        ignoreWorkspaceRootCheck: true,
        ignoreEngines: true,
        ignorePlatform: true,
        dev: devRequirement(requirements),
        optional: optionalRequirement(requirements),
    };
    const reporter = new EventReporter();
    const config = new Config(reporter);
    await config.init({
        cwd: path_1.default.join(directory, path_1.default.dirname(requirements.file)),
        nonInteractive: true,
        enableDefaultRc: true,
        extraneousYarnrcFiles: [".yarnrc"],
    });
    config.enableLockfileVersions = Boolean(originalYarnLock.match(/^# yarn v/m));
    const lockfile = await Lockfile.fromDirectory(directory, reporter);
    // Just as if we'd run `yarn add package@version`, but using our lightweight
    // implementation of Add that doesn't actually download and install packages
    const manifest = await config.readRootManifest();
    const existingVersionRequirement = flattenAllDependencies(manifest)[depName];
    const args = installArgsWithVersion(depName, desiredVersion, requirements, existingVersionRequirement);
    const add = new helpers_js_1.LightweightAdd(args, flags, config, reporter, lockfile);
    // Despite the innocent-sounding name, this actually does all the hard work
    await add.init();
    const dedupedYarnLock = (0, fix_duplicates_js_1.default)(readFile("yarn.lock"), depName);
    const newVersionRequirement = requirements.requirement;
    // Replace the version requirement in the lockfile (which will currently be an
    // exact version, not a requirement range)
    // If we don't have new requirement (e.g. git source) use the existing version
    // requirement from the package manifest
    const replacedDeclarationYarnLock = (0, replace_lockfile_declaration_js_1.default)(originalYarnLock, dedupedYarnLock, depName, newVersionRequirement, existingVersionRequirement);
    // Do a normal install to ensure the lockfile doesn't change when we do
    fs_1.default.writeFileSync(path_1.default.join(directory, "yarn.lock"), replacedDeclarationYarnLock);
    fs_1.default.writeFileSync(path_1.default.join(directory, requirements.file), originalPackageJson);
    const lockfile2 = await Lockfile.fromDirectory(directory, reporter);
    const install2 = new helpers_js_1.LightweightInstall(flags, config, reporter, lockfile2);
    await install2.init();
    let updatedYarnLock = readFile("yarn.lock");
    updatedYarnLock = recoverVersionComments(originalYarnLock, updatedYarnLock);
    return {
        "yarn.lock": updatedYarnLock,
    };
}
//# sourceMappingURL=updater.js.map