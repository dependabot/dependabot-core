#!/usr/bin/env node

const process = require('process');

function output(obj) {
  process.stdout.write(JSON.stringify(obj));
}

const input = [];
process.stdin.on("data", (data) => input.push(data));
process.stdin.on("end", () => {
  const request = JSON.parse(input.join(""));
  const [manager, functionName] = request.function.split(":");
  const helpers = require(`./lib/${manager}`);
  const func = helpers[functionName];
  if (!func) {
    output({ error: `Invalid function ${request.function}` });
    process.exit(1);
  }

  try {
    func
      .apply(null, request.args)
      .then((result) => {
        output({ result: result });
      })
      .catch((error) => {
        output({ error: error.message });
        process.exit(1);
      });
  } catch (e) {
    output({ error: `Error calling function: ${func.name}: ${e}` });
    process.exit(1);
  }
});
