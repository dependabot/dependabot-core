#!/usr/bin/env node
"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const process_1 = __importDefault(require("process"));
const npm = __importStar(require("./lib/npm/index.js"));
const npm6 = __importStar(require("./lib/npm6/index.js"));
const pnpm = __importStar(require("./lib/pnpm/index.js"));
const yarn = __importStar(require("./lib/yarn/index.js"));
function output(obj) {
    process_1.default.stdout.write(JSON.stringify(obj));
}
const managers = {
    npm,
    npm6,
    pnpm,
    yarn,
};
const input = [];
process_1.default.stdin.on("data", (data) => input.push(data));
process_1.default.stdin.on("end", () => {
    const request = JSON.parse(input.join(""));
    const [manager, functionName] = request.function.split(":");
    const helpers = managers[manager];
    if (!helpers) {
        output({ error: `Invalid manager ${manager}` });
        process_1.default.exit(1);
    }
    const func = helpers[functionName];
    if (!func) {
        output({ error: `Invalid function ${request.function}` });
        process_1.default.exit(1);
    }
    func(...request.args)
        .then((result) => {
        output({ result: result });
    })
        .catch((error) => {
        output({ error: error.message });
        process_1.default.exit(1);
    });
});
//# sourceMappingURL=run.js.map