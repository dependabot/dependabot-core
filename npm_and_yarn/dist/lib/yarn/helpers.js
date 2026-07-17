"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LightweightInstall = exports.LightweightAdd = exports.LOCKFILE_ENTRY_REGEX = void 0;
exports.isString = isString;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { Add } = require("@dependabot/yarn-lib/lib/cli/commands/add");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { Install } = require("@dependabot/yarn-lib/lib/cli/commands/install");
function isString(value) {
    return Object.prototype.toString.call(value) === "[object String]";
}
// Add is a subclass of the Install CLI command, which is responsible for
// adding packages to a package.json and yarn.lock. Upgrading a package is
// exactly the same as adding, except the package already exists in the
// manifests.
//
// Usually, calling Add.init() would execute a series of steps: resolve, fetch,
// link, run lifecycle scripts, cleanup, then save new manifest (package.json).
// We only care about the first and last steps: resolve, then save the new
// manifest. Fortunately, overriding bailout() gives us an opportunity to skip
// over the intermediate steps in a relatively painless fashion.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
class LightweightAdd extends Add {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(...args) {
        super(...args);
    }
    // This method is called by init() at the end of the resolve step, and is
    // responsible for checking if any dependencies need to be updated locally.
    // If everything is up to date, it'll save a new lockfile and return true,
    // which causes init() to skip over the next few steps (fetching and
    // installing packages). If there are packages that need updating, it'll
    // return false, and init() will continue on to the fetching and installing
    // steps.
    //
    // Add overrides Install's implementation to always return false - meaning
    // that it will always continue to the fetch and install steps. We want to
    // do the opposite - just save the new lockfile and stop there.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async bailout(patterns, workspaceLayout) {
        // This is the only part of the original bailout implementation that
        // matters: saving the new lockfile
        await this.saveLockfileAndIntegrity(patterns, workspaceLayout);
        // Skip over the unnecessary steps - fetching and linking packages, etc.
        return true;
    }
}
exports.LightweightAdd = LightweightAdd;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
class LightweightInstall extends Install {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    constructor(...args) {
        super(...args);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    async bailout(patterns, workspaceLayout) {
        await this.saveLockfileAndIntegrity(patterns, workspaceLayout);
        return true;
    }
}
exports.LightweightInstall = LightweightInstall;
exports.LOCKFILE_ENTRY_REGEX = /^(.*)@([^@]*?)$/;
//# sourceMappingURL=helpers.js.map