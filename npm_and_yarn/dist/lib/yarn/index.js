"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findConflictingDependencies = exports.checkPeerDependencies = exports.updateSubdependency = exports.update = exports.parseLockfile = void 0;
const lockfile_parser_js_1 = require("./lockfile-parser.js");
Object.defineProperty(exports, "parseLockfile", { enumerable: true, get: function () { return lockfile_parser_js_1.parse; } });
const updater_js_1 = require("./updater.js");
Object.defineProperty(exports, "update", { enumerable: true, get: function () { return updater_js_1.updateDependencyFiles; } });
const subdependency_updater_js_1 = require("./subdependency-updater.js");
Object.defineProperty(exports, "updateSubdependency", { enumerable: true, get: function () { return subdependency_updater_js_1.updateDependencyFile; } });
const peer_dependency_checker_js_1 = require("./peer-dependency-checker.js");
Object.defineProperty(exports, "checkPeerDependencies", { enumerable: true, get: function () { return peer_dependency_checker_js_1.checkPeerDependencies; } });
const conflicting_dependency_parser_js_1 = require("./conflicting-dependency-parser.js");
Object.defineProperty(exports, "findConflictingDependencies", { enumerable: true, get: function () { return conflicting_dependency_parser_js_1.findConflictingDependencies; } });
//# sourceMappingURL=index.js.map