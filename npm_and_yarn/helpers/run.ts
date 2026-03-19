#!/usr/bin/env node

import process from "process";
import * as npm from "./lib/npm/index.js";
import * as npm6 from "./lib/npm6/index.js";
import * as pnpm from "./lib/pnpm/index.js";
import * as yarn from "./lib/yarn/index.js";

function output(obj: object): void {
  process.stdout.write(JSON.stringify(obj));
}

const managers: Record<string, Record<string, (...args: any[]) => Promise<any>>> = {
  npm,
  npm6,
  pnpm,
  yarn,
};

const input: Buffer[] = [];
process.stdin.on("data", (data) => input.push(data));
process.stdin.on("end", () => {
  const request = JSON.parse(input.join(""));
  const [manager, functionName] = request.function.split(":");
  const helpers = managers[manager];
  if (!helpers) {
    output({ error: `Invalid manager ${manager}` });
    process.exit(1);
  }
  const func = helpers[functionName];
  if (!func) {
    output({ error: `Invalid function ${request.function}` });
    process.exit(1);
  }

  func
    .apply(null, request.args)
    .then((result: any) => {
      output({ result: result });
    })
    .catch((error: Error) => {
      output({ error: error.message });
      process.exit(1);
    });
});
