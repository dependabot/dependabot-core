const parser = require("../lib/parser");

describe("parser", () => {
  const dir = "test/fixtures/parser";

  it("returns an entry for each npm dependency", async () => {
    const deps = await parser.parse(dir);
    expect(deps.map(d => d.name).sort()).toEqual(
      expect.arrayContaining(["jq-accordion", "left-pad", "lodash"])
    );
  });

  it("excludes git dependencies", async () => {
    const deps = await parser.parse(dir);
    expect(deps.map(d => d.name).sort()).not.toContain("is-number");
  });

  it("excludes path-based dependencies", async () => {
    const deps = await parser.parse(dir);
    expect(deps.map(d => d.name).sort()).not.toContain("is-promise");
  });

  it("gets the version from the yarn.lock, not the package.json", async () => {
    const deps = await parser.parse(dir);
    const leftPad = deps.find(d => d.name === "left-pad");
    expect(leftPad.version).toEqual("1.1.1");
  });

  it("cleans the version string (e.g. strip leading 'v')", async () => {
    const deps = await parser.parse(dir);
    const jqAccordion = deps.find(d => d.name === "jq-accordion");
    expect(jqAccordion.version).toEqual("1.0.1");
  });

  it("ignores dependencies that are missing from the yarn.lock", async () => {
    const deps = await parser.parse(dir + "/yarn-lock-missing-dep");
    expect(deps.length).toEqual(0);
  });
});
