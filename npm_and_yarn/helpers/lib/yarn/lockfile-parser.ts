/* YARN.LOCK PARSER
 *
 * Inputs:
 *  - directory containing a yarn.lock
 *
 * Outputs:
 *  - JSON formatted yarn.lock
 */
import fs from "fs";
import path from "path";
// eslint-disable-next-line @typescript-eslint/no-require-imports
const parseLockfile = require("@dependabot/yarn-lib/lib/lockfile/parse").default;

export async function parse(directory: string): Promise<any> {
  const readFile = (fileName: string) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile(data).object;
}
