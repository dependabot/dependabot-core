"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.vulnerabilityAuditor = exports.findConflictingDependencies = void 0;
const conflicting_dependency_parser_js_1 = require("./conflicting-dependency-parser.js");
Object.defineProperty(exports, "findConflictingDependencies", { enumerable: true, get: function () { return conflicting_dependency_parser_js_1.findConflictingDependencies; } });
const vulnerability_auditor_js_1 = require("./vulnerability-auditor.js");
Object.defineProperty(exports, "vulnerabilityAuditor", { enumerable: true, get: function () { return vulnerability_auditor_js_1.findVulnerableDependencies; } });
//# sourceMappingURL=index.js.map