var exec = require('child_process').exec, child;

async function update(){
    child = exec('yarn update',
    function (error, stdout, stderr) {
        console.log('stdout: ' + stdout);
        console.log('stderr: ' + stderr);
        if (error !== null) {
             console.log('exec error: ' + error);
        }
    });
}

module.exports = { update }