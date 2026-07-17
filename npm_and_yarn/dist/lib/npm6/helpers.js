"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runAsync = runAsync;
exports.muteStderr = muteStderr;
/* eslint-disable @typescript-eslint/no-explicit-any */
function runAsync(obj, method, args) {
    return new Promise((resolve, reject) => {
        const cb = (err, ...returnValues) => {
            if (err) {
                reject(err);
            }
            else {
                resolve(returnValues);
            }
        };
        method.apply(obj, [...args, cb]);
    });
}
function muteStderr() {
    const original = process.stderr.write;
    process.stderr.write = (() => { });
    return () => {
        process.stderr.write = original;
    };
}
//# sourceMappingURL=helpers.js.map