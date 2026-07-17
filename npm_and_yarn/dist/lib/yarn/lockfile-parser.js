"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.parse = parse;
/* YARN.LOCK PARSER
 *
 * Inputs:
 *  - directory containing a yarn.lock
 *
 * Outputs:
 *  - JSON formatted yarn.lock
 */
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const parseLockfile = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/lockfile/parse").default;
async function parse(directory) {
    const readFile = (fileName) => fs_1.default.readFileSync(path_1.default.join(directory, fileName)).toString();
    const data = readFile("yarn.lock");
    return parseLockfile(data).object;
}
//# sourceMappingURL=lockfile-parser.js.map