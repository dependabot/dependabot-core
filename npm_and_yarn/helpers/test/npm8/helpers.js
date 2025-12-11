const path = require("path");
const fs = require("fs");

function loadFixture(fixture) {
  return fs.readFileSync(
    path.join(__dirname, `fixtures/${fixture}`),
    "utf8"
  );
}

function copyDependencies(sourceDir, destDir) {
  const fixtureDir = path.join(__dirname, "fixtures", sourceDir);
  fs.readdirSync(fixtureDir).forEach((file) => {
    fs.copyFileSync(path.join(fixtureDir, file), path.join(destDir, file));
  });
}

module.exports = { loadFixture, copyDependencies };
