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
const parseLockfile =
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  require("@dependabot/yarn-lib/lib/lockfile/parse").default;

export interface LockfileEntry {
  version: string;
  resolved?: string;
  dependencies?: Record<string, string>;
}

export async function parse(
  directory: string
): Promise<Record<string, LockfileEntry>> {
  const readFile = (fileName: string) =>
    fs.readFileSync(path.join(directory, fileName)).toString();
  const data = readFile("yarn.lock");
  return parseLockfile(data).object;
}
