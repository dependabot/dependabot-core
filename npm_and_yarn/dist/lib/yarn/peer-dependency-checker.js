"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkPeerDependencies = checkPeerDependencies;
/* PEER DEPENDENCY CHECKER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *  - requirements for this dependency
 *
 * Outputs:
 *  - successful completion, or an error if there are peer dependency warnings
 */
const path_1 = __importDefault(require("path"));
const helpers_js_1 = require("./helpers.js");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { Add } = require("@dependabot/yarn-lib/lib/cli/commands/add");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Config = require("@dependabot/yarn-lib/lib/config").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { BufferReporter } = require("@dependabot/yarn-lib/lib/reporters");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const fetcher = require("@dependabot/yarn-lib/lib/package-fetcher.js");
// Check peer dependencies without downloading node_modules or updating
// package/lockfiles
//
// Logic copied from the import command
// eslint-disable-next-line @typescript-eslint/no-explicit-any
class LightweightAdd extends Add {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(...args) {
        super(...args);
    }
    async bailout() {
        const manifests = await fetcher.fetch(this.resolver.getManifests(), this.config);
        this.resolver.updateManifests(manifests);
        await this.linker.resolvePeerModules();
        return true;
    }
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
function installArgsWithVersion(depName, desiredVersion, requirements) {
    const source = "source" in requirements
        ? requirements.source
        : (requirements.find((req) => req.source) || {})
            .source;
    const req = "requirement" in requirements
        ? requirements.requirement
        : (requirements.find((req) => req.requirement) || {})
            .requirement;
    if (source && source.type === "git") {
        if (desiredVersion) {
            return [`${depName}@${source.url}#${desiredVersion}`];
        }
        else {
            return [`${depName}@${source.url}`];
        }
    }
    else {
        return [`${depName}@${desiredVersion || req}`];
    }
}
async function checkPeerDependencies(directory, depName, desiredVersion, requirements) {
    for (const req of requirements) {
        await checkPeerDepsForReq(directory, depName, desiredVersion, req);
    }
}
async function checkPeerDepsForReq(directory, depName, desiredVersion, requirement) {
    const flags = {
        ignoreScripts: true,
        ignoreWorkspaceRootCheck: true,
        ignoreEngines: true,
        ignorePlatform: true,
        dev: devRequirement(requirement),
        optional: optionalRequirement(requirement),
    };
    const reporter = new BufferReporter();
    const config = new Config(reporter);
    await config.init({
        cwd: path_1.default.join(directory, path_1.default.dirname(requirement.file)),
        nonInteractive: true,
        enableDefaultRc: true,
        extraneousYarnrcFiles: [".yarnrc"],
    });
    const lockfile = await Lockfile.fromDirectory(directory, reporter);
    // Returns dep name and version for yarn add, example: ["react@16.6.0"]
    const args = installArgsWithVersion(depName, desiredVersion, requirement);
    // Just as if we'd run `yarn add package@version`, but using our lightweight
    // implementation of Add that doesn't actually download and install packages
    const add = new LightweightAdd(args, flags, config, reporter, lockfile);
    await add.init();
    const eventBuffer = reporter.getBuffer();
    const peerDependencyWarnings = eventBuffer
        .map(({ data }) => data)
        .filter((data) => {
        // Guard against event.data sometimes being an object
        return (0, helpers_js_1.isString)(data) && data.match(/(unmet|incorrect) peer dependency/);
    });
    if (peerDependencyWarnings.length) {
        throw new Error(peerDependencyWarnings.join("\n"));
    }
}
//# sourceMappingURL=peer-dependency-checker.js.map