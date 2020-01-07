const fs = require("fs");
const path = require("path")
var exec = require('child_process').exec, child;

async function runRushUpdate(rootPath, shrinkwrapFilePath){
    child = exec('node common/scripts/install-run-rush.js update -p --no-link --bypass-policy',
                    function (error, stdout, stderr) {
                        if (error !== null) {
                            console.log('exec error: ' + error);
                        }
                    });
    
    const updateFileContent = fs.readFileSync(path.join(rootPath, shrinkwrapFilePath)).toString()
    // return { shrinkwrapFilePath: updateFileContent };
    return { updateFileContent };
}

module.exports = { runRushUpdate }