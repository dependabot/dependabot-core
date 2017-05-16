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
const { Install } = require('yarn/lib/cli/commands/install');
const Config = require('yarn/lib/config').default;
const { NoopReporter } = require('yarn/lib/reporters');
const Lockfile = require('yarn/lib/lockfile/wrapper').default;

function parse(directory) {
  const flags = { ignoreScripts: true };
  const reporter = new NoopReporter();
  const config = new Config(reporter);
  return config.init({ cwd: directory })
    .then(() => Lockfile.fromDirectory(directory, reporter))
    .then(lockfile => {
      const install = new Install(flags, config, reporter, lockfile);
      return install.fetchRequestFromCwd()
        .then(({ requests }) => requests.map(request => request.pattern))
        .then(patterns => patterns.map(pattern => lockfile.getLocked(pattern)))
        .then(deps => deps.map(d => ({ name: d.name, version: d.version })))
    });
}

module.exports = { parse };
