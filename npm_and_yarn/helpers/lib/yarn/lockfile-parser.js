/* YARN.LOCK PARSER
 *
 * Inputs:
 *  - directory containing a yarn.lock
 *
 * Outputs:
 *  - JSON formatted yarn.lock
 */
const fs = require("fs");
const path = require("path");
const parseLockfile = require("@dependabot/yarn-lib/lib/lockfile/parse")
  .default;
// const { parseSyml } = require("@yarnpkg/parsers")

async function parse(directory) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  let lockfile;
  lockfile = parseLockfile(data).object;

  // // If the lockfile contains a "__metadata" key, it's safe to assume it's a
  // // yarn Berry lockfile, and we should use its parser.
  // if (lockfile && lockfile.__metadata) {
  //   lockfile = parseSyml(data);
  // }

  return lockfile
}

module.exports = { parse };
