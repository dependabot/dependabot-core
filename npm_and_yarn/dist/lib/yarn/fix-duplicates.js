"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = fixDuplicates;
const semver_1 = __importDefault(require("semver"));
const helpers_js_1 = require("./helpers.js");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const parse = require("@dependabot/yarn-lib/lib/lockfile/parse").default;
const stringify = 
// eslint-disable-next-line @typescript-eslint/no-require-imports
require("@dependabot/yarn-lib/lib/lockfile/stringify").default;
function flattenIndirectDependencies(packages) {
    return (packages || []).reduce((acc, { pkg }) => {
        if (pkg.dependencies) {
            return acc.concat(Object.keys(pkg.dependencies));
        }
        return acc;
    }, []);
}
// Inspired by yarn-deduplicate. Altered to ensure the latest version is always used
// for version ranges which allow it.
function fixDuplicates(data, updatedDependencyName) {
    if (!updatedDependencyName) {
        throw new Error("Yarn fix duplicates: must provide dependency name");
    }
    const json = parse(data).object;
    const enableLockfileVersions = !!data.match(/^# yarn v/m);
    const noHeader = !data.match(/^# THIS IS AN AU/m);
    const packages = {};
    Object.entries(json).forEach(([name, pkg]) => {
        if (name.match(helpers_js_1.LOCKFILE_ENTRY_REGEX)) {
            const match = name.match(helpers_js_1.LOCKFILE_ENTRY_REGEX);
            const [, packageName, requestedVersion] = match;
            packages[packageName] = packages[packageName] || [];
            packages[packageName].push(Object.assign({}, {
                name,
                pkg: pkg,
                packageName,
                requestedVersion,
            }));
        }
    });
    const packageEntries = Object.entries(packages);
    const updatedPackageEntry = packageEntries.filter(([name]) => {
        return updatedDependencyName === name;
    });
    const updatedDependencyPackage = updatedPackageEntry[0] && updatedPackageEntry[0][1];
    const indirectDependencies = flattenIndirectDependencies(updatedDependencyPackage);
    const packagesToDedupe = [updatedDependencyName, ...indirectDependencies];
    packageEntries
        .filter(([name]) => packagesToDedupe.includes(name))
        .forEach(([name, packages]) => {
        // Reverse sort, so we'll find the maximum satisfying version first
        const versions = packages.map((p) => p.pkg.version).sort(semver_1.default.rcompare);
        // Dedup each package to its maxSatisfying version
        packages.forEach((p) => {
            const targetVersion = semver_1.default.maxSatisfying(versions, p.requestedVersion);
            if (targetVersion === null)
                return;
            if (targetVersion !== p.pkg.version) {
                const dedupedPackage = packages.find((p) => p.pkg.version === targetVersion);
                json[`${name}@${p.requestedVersion}`] = dedupedPackage.pkg;
            }
        });
    });
    return stringify(json, noHeader, enableLockfileVersions);
}
//# sourceMappingURL=fix-duplicates.js.map