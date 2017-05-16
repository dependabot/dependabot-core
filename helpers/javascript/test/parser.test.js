const parser = require("../lib/parser");
const helpers = require("./helpers");

describe("parser", () => {
  const dir = "test/fixtures/parser";

  it("returns an entry for each dependency", done => {
    parser.parse(dir).then(deps => expect(deps.length).toEqual(2)).then(done);
  });

  it("gets the version from the yarn.lock, not the package.json", done => {
    parser
      .parse(dir)
      .then(deps => {
        const leftPad = deps.find(d => d.name === "left-pad");
        expect(leftPad.version).toEqual("1.1.1");
      })
      .then(done);
  });
});
