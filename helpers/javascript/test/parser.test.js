const parser = require("../lib/parser");
const helpers = require("./helpers");

describe("parser", () => {
  const dir = "test/fixtures/parser";

  it("returns an entry for each dependency", async () => {
    const deps = await parser.parse(dir);
    expect(deps.length).toEqual(2);
  });

  it("gets the version from the yarn.lock, not the package.json", async () => {
    const deps = await parser.parse(dir);
    const leftPad = deps.find(d => d.name === "left-pad");
    expect(leftPad.version).toEqual("1.1.1");
  });
});
