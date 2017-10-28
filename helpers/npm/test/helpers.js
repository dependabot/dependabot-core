const path = require("path");
const fs = require("fs");

module.exports = {
  loadFixture: fixturePath =>
    fs.readFileSync(path.join("test", "fixtures", fixturePath)).toString()
};
