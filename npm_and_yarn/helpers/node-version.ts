#!/usr/bin/env node

import process from "process";
import { matchNodeVersions } from "./lib/npm/node-version.js";

const input: Buffer[] = [];
process.stdin.on("data", (data) => input.push(data));
process.stdin.on("end", () => {
  const request: { args: [string[], string[]] } = JSON.parse(input.join(""));
  matchNodeVersions(...request.args)
    .then((result) => process.stdout.write(JSON.stringify({ result })))
    .catch((error: Error) => {
      process.stdout.write(JSON.stringify({ error: error.message }));
      process.exit(1);
    });
});
