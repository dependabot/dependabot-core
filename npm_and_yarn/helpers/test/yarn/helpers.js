const path = require("path");
const fs = require("fs");

module.exports = {
  loadFixture: fixturePath =>
    fs.readFileSync(path.join(__dirname, "fixtures", fixturePath)).toString()
};
