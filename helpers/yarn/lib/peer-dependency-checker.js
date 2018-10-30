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
const { EventReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;

class LightweightAdd extends Add {
  async bailout(patterns, workspaceLayout) {
    await this.linker.resolvePeerModules();
    return true;
  }
}

class DependabotReporter extends EventReporter {
  warn(msg) {
    if (msg.includes("incorrect peer dependency")) {
      throw new Error(msg);
    }
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

function install_args_with_version(depName, desiredVersion, requirements) {
  const source = requirements.source;

  if (source && source.type === "git") {
    return [`${depName}@${source.url}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
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
  const reporter = new DependabotReporter();
  const config = new Config(reporter);
  await config.init({
    cwd: path.join(directory, path.dirname(requirement.file)),
    nonInteractive: true,
    enableDefaultRc: true
  });

  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  // Just as if we'd run `yarn add package@version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const args = install_args_with_version(depName, desiredVersion, requirement);
  const add = new LightweightAdd(args, flags, config, reporter, lockfile);

  // Despite the innocent-sounding name, this actually does all the hard work
  await add.init();
}

module.exports = { checkPeerDependencies };
