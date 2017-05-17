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
const { Install } = require("yarn/lib/cli/commands/install");
const Config = require("yarn/lib/config").default;
const { NoopReporter } = require("yarn/lib/reporters");
const Lockfile = require("yarn/lib/lockfile/wrapper").default;

async function parse(directory) {
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const lockfile = await Lockfile.fromDirectory(directory, reporter);

  const config = new Config(reporter);
  await config.init({ cwd: directory });

  const install = new Install(flags, config, reporter, lockfile);
  const { requests } = await install.fetchRequestFromCwd();
  const deps = requests.map(request => lockfile.getLocked(request.pattern));

  return deps.map(dep => ({ name: dep.name, version: dep.version }));
}

module.exports = { parse };
