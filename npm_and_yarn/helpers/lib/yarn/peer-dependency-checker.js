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
const path = require("path");
const { Add } = require("@dependabot/yarn-lib/lib/cli/commands/add");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { BufferReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const { isString } = require("./helpers");
const fetcher = require("@dependabot/yarn-lib/lib/package-fetcher.js");

// Check peer dependencies without downloading node_modules or updating
// package/lockfiles
//
// Logic copied from the import command
class LightweightAdd extends Add {
  async bailout() {
    const manifests = await fetcher.fetch(
      this.resolver.getManifests(),
      this.config
    );
    this.resolver.updateManifests(manifests);
    await this.linker.resolvePeerModules();
    return true;
  }
}

function devRequirement(requirements) {
  const groups = requirements.groups;
  return (
    groups.indexOf("devDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function optionalRequirement(requirements) {
  const groups = requirements.groups;
  return (
    groups.indexOf("optionalDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function installArgsWithVersion(depName, desiredVersion, requirements) {
  const source =
    "source" in requirements
      ? requirements.source
      : (requirements.find(req => req.source) || {}).source;
  const req =
    "requirement" in requirements
      ? requirements.requirement
      : (requirements.find(req => req.requirement) || {}).requirement;

  if (source && source.type === "git") {
    if (desiredVersion) {
      return [`${depName}@${source.url}#${desiredVersion}`];
    } else {
      return [`${depName}@${source.url}`];
    }
  } else {
    return [`${depName}@${desiredVersion || req}`];
  }
}

async function checkPeerDependencies(
  directory,
  depName,
  desiredVersion,
  requirements
) {
  for (let req of requirements) {
    await checkPeerDepsForReq(directory, depName, desiredVersion, req);
  }
}

async function checkPeerDepsForReq(
  directory,
  depName,
  desiredVersion,
  requirement
) {
  const flags = {
    ignoreScripts: true,
    ignoreWorkspaceRootCheck: true,
    ignoreEngines: true,
    dev: devRequirement(requirement),
    optional: optionalRequirement(requirement)
  };
  const reporter = new BufferReporter();
  const config = new Config(reporter);

  await config.init({
    cwd: path.join(directory, path.dirname(requirement.file)),
    nonInteractive: true,
    enableDefaultRc: true
  });

  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  // Returns dep name and version for yarn add, example: ["react@16.6.0"]
  let args = installArgsWithVersion(depName, desiredVersion, requirement);

  // Just as if we'd run `yarn add package@version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const add = new LightweightAdd(args, flags, config, reporter, lockfile);

  await add.init();

  const eventBuffer = reporter.getBuffer();
  const peerDependencyWarnings = eventBuffer
    .map(({ data }) => data)
    .filter(data => {
      // Guard against event.data sometimes being an object
      return isString(data) && data.match(/(unmet|incorrect) peer dependency/);
    });

  if (peerDependencyWarnings.length) {
    throw new Error(peerDependencyWarnings.join("\n"));
  }
}

module.exports = { checkPeerDependencies };
