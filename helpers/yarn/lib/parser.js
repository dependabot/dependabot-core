/* DEPENDENCY FILE PARSER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *
 * Outputs:
 *  - list of dependencies and their current versions
 *
 * Extract a list of the packages specified in the package.json, with their
 * currently installed versions (which are in the yarn.lock)
 */
const { Install } = require("@dependabot/yarn-lib/lib/cli/commands/install");
const Config = require("@dependabot/yarn-lib/lib/config").default;
const { NoopReporter } = require("@dependabot/yarn-lib/lib/reporters");
const Lockfile = require("@dependabot/yarn-lib/lib/lockfile").default;
const PackageRequest = require("@dependabot/yarn-lib/lib/package-request")
  .default;
const {
  normalizePattern
} = require("@dependabot/yarn-lib/lib/util/normalize-pattern");
const { getExoticResolver } = require("@dependabot/yarn-lib/lib/resolvers");
const semver = require("semver");

function isNotExotic(request) {
  const { range } = normalizePattern(request.pattern);
  return !getExoticResolver(range);
}

function isNotPrivate(dep) {
  const re = /registry\.yarnpkg\.com/;
  return re.test(dep.resolved);
}

async function parse(directory) {
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  const config = new Config(reporter);
  await config.init({ cwd: directory });

  const install = new Install(flags, config, reporter, lockfile);
  const { requests, patterns } = await install.fetchRequestFromCwd();
  const deps = requests
    .filter(isNotExotic)
    .map(request => lockfile.getLocked(request.pattern))
    .filter(dep => dep)
    .filter(isNotPrivate);

  return deps.map(dep => ({
    name: dep.name,
    resolved: dep.resolved,
    version: semver.clean(dep.version)
  }));
}

module.exports = { parse };
