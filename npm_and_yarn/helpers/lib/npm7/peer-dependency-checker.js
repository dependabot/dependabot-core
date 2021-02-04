/* PEER DEPENDENCY CHECKER
 *
 * Inputs:
 *  - directory containing a package.json and a yarn.lock
 *  - dependency name
 *  - new dependency version
 *  - requirements for this dependency
 *
 * Outputs:
 *  - successful completion, or an error if there are peer dependency warnings
 */

const npm = require("npm7");
const Arborist = require("@npmcli/arborist");

function installArgsWithVersion(depName, desiredVersion, reqs) {
  const source = (reqs.find((req) => req.source) || {}).source;

  if (source && source.type === "git") {
    return [`${depName}@${source.url}#${desiredVersion}`];
  } else {
    return [`${depName}@${desiredVersion}`];
  }
}

async function checkPeerDependencies(
  directory,
  depName,
  desiredVersion,
  requirements,
  _topLevelDependencies // included for compatibility with npm 6 implementation
) {
  await new Promise((resolve) => {
    npm.load(resolve);
  });

  // `ignoreScripts` is used to disable prepare and prepack scripts which are
  // run when installing git dependencies
  const arb = new Arborist({
    ...npm.flatOptions,
    path: directory,
    packageLockOnly: true,
    dryRun: true,
    save: false,
    ignoreScripts: true,
    engineStrict: false,
    // NOTE: there seems to be no way to disable platform checks in arborist
    // without force installing invalid peer dependencies
    //
    // TODO: ignore platform checks
    force: false,
  });

  // Returns dep name and version for npm install, example: ["react@16.6.0"]
  let args = installArgsWithVersion(depName, desiredVersion, requirements);

  return await arb
    .buildIdealTree({
      add: args,
    })
    .catch((er) => {
      if (er.code === "ERESOLVE") {
        // NOTE: Emulate the error message in npm 6 for compatibility with the
        // version resolver
        const conflictingDependencies = [
          `${er.edge.from.name}@${er.edge.from.version} requires a peer of ${er.current.name}@${er.edge.spec} but none is installed.`,
        ];
        throw new Error(conflictingDependencies.join("\n"));
      } else {
        // NOTE: Hand over exception handling to the file updater. This is
        // consistent with npm6 behaviour.
        return [];
      }
    })
    .then(() => []);
}

module.exports = { checkPeerDependencies };
