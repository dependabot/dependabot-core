import semver from "semver";

export async function matchNodeVersions(
  versions: string[],
  requirements: string[],
): Promise<{ invalidRequirement: string | null; version: string | null }> {
  const invalidRequirement =
    requirements.find((range) => semver.validRange(range) === null) ?? null;
  if (invalidRequirement !== null) {
    return { invalidRequirement, version: null };
  }

  const ranges = requirements.map((range) => new semver.Range(range));
  const version =
    versions.find((candidate) =>
      ranges.every((range) => range.test(candidate)),
    ) ?? null;
  return { invalidRequirement, version };
}
