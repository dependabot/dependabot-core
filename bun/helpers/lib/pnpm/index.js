const lockfileParser = require("./lockfile-parser");

module.exports = {
  parseLockfile: lockfileParser.parse,
};
