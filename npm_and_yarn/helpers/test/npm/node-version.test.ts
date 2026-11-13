import { matchNodeVersions } from "../../lib/npm/node-version.js";

describe("matchNodeVersions", () => {
  const versions = ["24.0.0", "22.1.0", "22.0.9", "20.19.5", "18.20.8"];

  it.each([
    ["x", "24.0.0"],
    ["22.x || X", "24.0.0"],
    ["18 - 22.0", "22.0.9"],
    ["<=22.x", "22.1.0"],
    [">22.x", "24.0.0"],
    ["^20.0.0 || ~22.0.0", "22.0.9"],
    [">=22.0.0-rc.1 <22.1.0", "22.0.9"],
  ])("matches npm range %s", async (range, expected) => {
    expect(await matchNodeVersions(versions, [range])).toEqual({
      invalidRequirement: null,
      version: expected,
    });
  });

  it("intersects requirements and rejects invalid ranges", async () => {
    expect(await matchNodeVersions(versions, ["18 - 22.0", "22.0.x"])).toEqual({
      invalidRequirement: null,
      version: "22.0.9",
    });
    expect(await matchNodeVersions(versions, ["not a range"])).toEqual({
      invalidRequirement: "not a range",
      version: null,
    });
  });
});
