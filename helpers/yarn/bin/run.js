const lockfileParser = require("../lib/lockfile-parser");
const updater = require("../lib/updater");

const functionMap = {
  parseLockfile: lockfileParser.parse,
  update: updater.updateDependencyFiles
};

function output(obj) {
  process.stdout.write(JSON.stringify(obj));
}

const input = [];
process.stdin.on("data", data => input.push(data));
process.stdin.on("end", () => {
  const request = JSON.parse(input.join(""));
  const func = functionMap[request.function];
  if (!func) {
    output({ error: `Invalid function ${request.function}` });
    process.exit(1);
  }

  func
    .apply(null, request.args)
    .then(result => {
      output({ result: result });
    })
    .catch(error => {
      output({ error: error.message });
      process.exit(1);
    });
});
