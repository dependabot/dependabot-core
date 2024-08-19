/* YARN.LOCK PARSER
 *
 * Inputs:
 *  - directory containing a yarn.lock
 *
 * Outputs:
 *  - JSON formatted yarn.lock
 */
import fs from "node:fs";
import path from "node:path";
import parseLockfile from "@dependabot/yarn-lib/lib/lockfile/parse";

export default async function parse(directory) {
  const readFile = (fileName) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile.default(data).object;
}
