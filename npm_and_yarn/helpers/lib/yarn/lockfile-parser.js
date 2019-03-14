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

async function parse(directory) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile(data).object;
}

module.exports = { parse };
