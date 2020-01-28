const fs = require("fs");
const path = require("path")
var exec = require('child_process').exec, child;

async function runRushUpdate(rootPath, shrinkwrapFilePath){

    return new Promise(resolve => {
    
        exec('node common/scripts/install-run-rush.js update --no-link --bypass-policy', { maxBuffer: 1024 * 1024 * 50 }, function(a,b,c) {
            const updateFileContent = fs.readFileSync(path.join(rootPath, shrinkwrapFilePath)).toString()
            // return { shrinkwrapFilePath: updateFileContent };
            return resolve(updateFileContent);
        });
    },
    //  TODO: Handle error as well 
    () => {});
}
module.exports = { runRushUpdate }
