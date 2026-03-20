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
import path from "path";
import { isString, type Requirement } from "./helpers.js";

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
class LightweightAdd extends (Add as any) {
  constructor(...args: any[]) {
    super(...args);
  }

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

function devRequirement(requirements: Requirement): boolean {
  const groups = requirements.groups;
  return (
    groups.indexOf("devDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function optionalRequirement(requirements: Requirement): boolean {
  const groups = requirements.groups;
  return (
    groups.indexOf("optionalDependencies") > -1 &&
    groups.indexOf("dependencies") == -1
  );
}

function installArgsWithVersion(
  depName: string,
  desiredVersion: string,
  requirements: Requirement | Requirement[]
): string[] {
  const source =
    "source" in requirements
      ? requirements.source
      : ((requirements as Requirement[]).find((req) => req.source) || {}).source;
  const req =
    "requirement" in requirements
      ? requirements.requirement
      : ((requirements as Requirement[]).find((req) => req.requirement) || {}).requirement;

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

export async function checkPeerDependencies(
  directory: string,
  depName: string,
  desiredVersion: string,
  requirements: Requirement[]
): Promise<void> {
  for (const req of requirements) {
    await checkPeerDepsForReq(directory, depName, desiredVersion, req);
  }
}

async function checkPeerDepsForReq(
  directory: string,
  depName: string,
  desiredVersion: string,
  requirement: Requirement
): Promise<void> {
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
    cwd: path.join(directory, path.dirname(requirement.file)),
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
    .map(({ data }: { data: unknown }) => data)
    .filter((data: unknown) => {
      // Guard against event.data sometimes being an object
      return isString(data) && data.match(/(unmet|incorrect) peer dependency/);
    });

  if (peerDependencyWarnings.length) {
    throw new Error(peerDependencyWarnings.join("\n"));
  }
}
