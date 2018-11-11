const npm6installer = require("npm/lib/install");
const npm5installer = require("npm5/node_modules/npm/lib/install");

function installerForLockfile(lockfile) {
  const requireObjectsIncludeMatchers = Object.keys(
    lockfile["dependencies"] || {}
  ).some(key => {
    const requires = lockfile["dependencies"][key]["requires"] || {};

    // npm6 changed the lockfile format to include version ranges in requires
    // whereas npm5 only saved the exact version
    return Object.keys(requires).some(key2 =>
      requires[key2].match(/^\^|~|\<|\>/)
    );
  });

  return requireObjectsIncludeMatchers ? npm6installer : npm5installer;
}

function runAsync(obj, method, args) {
  return new Promise((resolve, reject) => {
    const cb = (err, ...returnValues) => {
      if (err) {
        reject(err);
      } else {
        resolve(returnValues);
      }
    };
    method.apply(obj, [...args, cb]);
  });
}

function muteStderr() {
  const original = process.stderr.write;
  process.stderr.write = () => {};
  return () => {
    process.stderr.write = original;
  };
}

module.exports = {
  installerForLockfile,
  runAsync,
  muteStderr
};
