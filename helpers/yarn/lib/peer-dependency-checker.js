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
  requirements,
  topLevelDependencies
) {
  for (let req of requirements) {
    await checkPeerDepsForReq(
      directory,
      depName,
      desiredVersion,
      req,
      topLevelDependencies
    );
  }
}

async function checkPeerDepsForReq(
  directory,
  depName,
  desiredVersion,
  requirement,
  topLevelDependencies
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

  // Returns dep name and version for yarn add, example: ["react@16.6.0"]
  let args = installArgsWithVersion(depName, desiredVersion, requirement);

  // To check peer dependencies requirements in all top level dependencies we
  // need to explicitly tell yarn to fetch all manifests by specifying the
  // existing dependency name and version in yarn add

  // For exampele, if we have "react@15.6.2" and "react-dom@15.6.2" installed
  // and we want to install react@16.6.0, we need get the existing version of
  // react-dom and pass this to yarn add along with the new version react, this
  // way yarn fetches the manifest for react-dom and determines that we can't
  // install react@16.6.0 due to the peer dependency requirement in react-dom

  // If we only pass the new dep@version to yarn add, e.g. "react@16.6.0" yarn
  // will only fetch the manifest for react and not know that react-dom enforces
  // a peerDependency on react

  // Returns dep name and version for yarn add, example: ["react-dom@15.6.2"]
  // - given react and react-dom in top level deps
  const otherDeps = (topLevelDependencies || [])
    .filter(dep => dep.name !== depName && dep.version)
    .map(dep => installArgsWithVersion(dep.name, dep.version, dep.requirements))
    .reduce((acc, dep) => acc.concat(dep), []);

  args = args.concat(otherDeps);

  // Just as if we'd run `yarn add package@version`, but using our lightweight
  // implementation of Add that doesn't actually download and install packages
  const add = new LightweightAdd(args, flags, config, reporter, lockfile);

  // Despite the innocent-sounding name, this actually does all the hard work
  await add.init();
}

module.exports = { checkPeerDependencies };
