/* DEPENDENCY FILE PARSER
 *
 * Inputs:
 *  - directory containing a build.gradle
 *
 * Outputs:
 *  - list of dependencies and their current versions
 *
 * Extract a list of the packages specified in the build.gradle
 */
const g2js = require('gradle-to-js/lib/parser');

async function parse(directory) {
  return g2js.parseFile('build.gradle').then(function(representation) {
    return JSON.stringify(representation)
  });
}

module.exports = { parse };
