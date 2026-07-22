import { LOCKFILE_ENTRY_REGEX } from "../../lib/yarn/helpers.js";

describe("LOCKFILE_ENTRY_REGEX", () => {
  it("matches a simple unscoped package", () => {
    const match = "left-pad@1.0.0".match(LOCKFILE_ENTRY_REGEX);
    expect(match).not.toBeNull();
    const [, packageName, requirement] = match!;
    expect(packageName).toBe("left-pad");
    expect(requirement).toBe("1.0.0");
  });

  it("matches a scoped package", () => {
    const match = "@scope/pkg@1.2.3".match(LOCKFILE_ENTRY_REGEX);
    expect(match).not.toBeNull();
    const [, packageName, requirement] = match!;
    expect(packageName).toBe("@scope/pkg");
    expect(requirement).toBe("1.2.3");
  });

  it("matches an unscoped package with a git URL containing @", () => {
    const key =
      "is-number@https://dummy-token@github.com/jonschlinkert/is-number.git#master";
    const match = key.match(LOCKFILE_ENTRY_REGEX);
    expect(match).not.toBeNull();
    const [, packageName, requirement] = match!;
    expect(packageName).toBe("is-number");
    expect(requirement).toBe(
      "https://dummy-token@github.com/jonschlinkert/is-number.git#master"
    );
  });

  it("matches a scoped package with a git URL containing multiple @ characters", () => {
    const key = "@scope/pkg@git+https://x@github.com/y/z";
    const match = key.match(LOCKFILE_ENTRY_REGEX);
    expect(match).not.toBeNull();
    const [, packageName, requirement] = match!;
    expect(packageName).toBe("@scope/pkg");
    expect(requirement).toBe("git+https://x@github.com/y/z");
  });
});
