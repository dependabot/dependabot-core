const parser = require("../lib/parser");

describe("parser", () => {
  const dir = "test/fixtures/parser";

  it("returns an entry for each npm dependency", async () => {
    const deps = await parser.parse(dir);
    expect(deps.map(d => d.name).sort()).toEqual(
      expect.arrayContaining(["left-pad", "lodash"])
    );
  });

  it("excludes 'exotic' dependencies (git, path, etc.)", async () => {
    const deps = await parser.parse(dir);
    expect(deps.map(d => d.name).sort()).not.toContain("is-number");
  });

  it("gets the version from the yarn.lock, not the package.json", async () => {
    const deps = await parser.parse(dir);
    const leftPad = deps.find(d => d.name === "left-pad");
    expect(leftPad.version).toEqual("1.1.1");
  });
});
