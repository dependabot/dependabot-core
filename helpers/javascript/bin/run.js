const parser = require("../lib/parser");

const methodMap = {
  parse: parser.parse
};

function output(obj) {
  process.stdout.write(JSON.stringify(obj));
}

const input = [];
process.stdin.on("data", data => input.push(data));
process.stdin.on("end", () => {
  const request = JSON.parse(input.join(""));
  const method = methodMap[request.method];
  if (!method) {
    output({ error: `Invalid method ${request.method}` });
    process.exit(1);
  }

  method
    .apply(null, request.args)
    .then(result => {
      output({ result: result });
    })
    .catch(error => {
      console.log(error.message);
      process.exit(1);
    });
});
