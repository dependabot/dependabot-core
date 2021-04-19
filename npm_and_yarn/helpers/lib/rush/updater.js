const fs = require("fs");
const path = require("path");
var exec = require("child_process").exec,
  child;

async function runRushUpdate(rootPath, shrinkwrapFilePath) {
  return new Promise((resolve, reject) => {
    process.env["RUSH_ALLOW_UNSUPPORTED_NODEJS"] = "true"; // bypass node engine compatibility check
    exec(
      "node common/scripts/install-run-rush.js update --bypass-policy",
      { maxBuffer: 1024 * 1024 * 50 },
      function (err, stdout, stderr) {
        if (err) {
          reject(err);
        }

        const updateFileContent = fs
          .readFileSync(path.join(rootPath, shrinkwrapFilePath))
          .toString();
        return resolve(updateFileContent);
      }
    );
  });
}

module.exports = { runRushUpdate };
