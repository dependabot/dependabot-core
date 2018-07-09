const fs = require("fs");
const path = require("path");
const parseLockfile = require("@dependabot/yarn-lib/lib/lockfile/parse")
  .default;

// Inspired by yarn-tools. Altered to ensure the latest version is always used
// for version ranges which allow it.
async function parse(directory) {
  const readFile = fileName =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile(data).object;
}

module.exports = { parse };
