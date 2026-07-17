"use strict";
/* PNPM-LOCK.YAML PARSER
 *
 * Inputs:
 *  - directory containing a pnpm-lock.yaml file
 *
 * Outputs:
 *  - JSON formatted information of dependencies (name, version, dependency-type)
 */
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.parse = parse;
const lockfile_file_1 = require("@pnpm/lockfile-file");
const dependencyPath = __importStar(require("@pnpm/dependency-path"));
async function parse(directory) {
    const lockfile = await (0, lockfile_file_1.readWantedLockfile)(directory, {
        ignoreIncompatible: true,
    });
    if (!lockfile) {
        return [];
    }
    return Object.entries(lockfile.packages ?? {})
        .filter(([depPath]) => {
        const dp = dependencyPath.parse(depPath);
        return dp && dp.name; // null or undefined checked for dependency path (dp) and empty name dps are filtered.
    })
        .map(([depPath, pkgSnapshot]) => nameVerDevFromPkgSnapshot(depPath, pkgSnapshot, Object.values(lockfile.importers)));
}
function nameVerDevFromPkgSnapshot(depPath, pkgSnapshot, projectSnapshots) {
    let name;
    let version;
    if (!pkgSnapshot.name) {
        const pkgInfo = dependencyPath.parse(depPath);
        name = pkgInfo.name ?? depPath;
        version = pkgInfo.version ?? "";
    }
    else {
        name = pkgSnapshot.name;
        version = pkgSnapshot.version ?? "";
    }
    const specifiers = [];
    let aliased = false;
    projectSnapshots.every((projectSnapshot) => {
        const projectSpecifiers = projectSnapshot.specifiers;
        if (Object.values(projectSpecifiers).some((specifier) => specifier.startsWith(`npm:${name}@`) || specifier == `npm:${name}`)) {
            aliased = true;
            return false;
        }
        const currentSpecifier = projectSpecifiers[name];
        if (!currentSpecifier) {
            return true;
        }
        const specifierVersion = projectSnapshot.dependencies?.[name] ||
            projectSnapshot.devDependencies?.[name] ||
            projectSnapshot.optionalDependencies?.[name];
        if (specifierVersion &&
            (specifierVersion == version ||
                specifierVersion.startsWith(`${version}_`) || // lockfileVersion 5.4
                specifierVersion.startsWith(`${version}(`)) // lockfileVersion 6.0
        ) {
            specifiers.push(currentSpecifier);
        }
        return true;
    });
    return {
        name: name,
        version: version,
        resolved: "tarball" in pkgSnapshot.resolution
            ? pkgSnapshot.resolution.tarball
            : undefined,
        dev: "dev" in pkgSnapshot && pkgSnapshot.dev === true,
        specifiers: specifiers,
        aliased: aliased,
    };
}
//# sourceMappingURL=lockfile-parser.js.map