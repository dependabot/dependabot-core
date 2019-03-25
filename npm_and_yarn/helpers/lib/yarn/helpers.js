const { Add } = require("@dependabot/yarn-lib/lib/cli/commands/add");
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
// manifest. Fotunately, overriding bailout() gives us an opportunity to skip
// over the intermediate steps in a relatively painless fashion.
class LightweightAdd extends Add {
  // This method is called by init() at the end of the resolve step, and is
  // responsible for checking if any dependnecies need to be updated locally.
  // If everything is up to date, it'll save a new lockfile and return true,
  // which causes init() to skip over the next few steps (fetching and
  // installing packages). If there are packages that need updating, it'll
  // return false, and init() will continue on to the fetching and installing
  // steps.
  //
  // Add overrides Install's implementation to always return false - meaning
  // that it will always continue to the fetch and install steps. We want to
  // do the opposite - just save the new lockfile and stop there.
  async bailout(patterns, workspaceLayout) {
    // This is the only part of the original bailout implementation that
    // matters: saving the new lockfile
    await this.saveLockfileAndIntegrity(patterns, workspaceLayout);

    // Skip over the unnecessary steps - fetching and linking packages, etc.
    return true;
  }
}

class LightweightInstall extends Install {
  async bailout(patterns, workspaceLayout) {
    await this.saveLockfileAndIntegrity(patterns, workspaceLayout);
    return true;
  }
}

module.exports = { isString, LightweightAdd, LightweightInstall };
