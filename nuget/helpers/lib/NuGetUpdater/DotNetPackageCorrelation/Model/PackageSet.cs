using Semver;

namespace DotNetPackageCorrelation;

public record PackageSet
{
    public SortedDictionary<string, SemVersion> Packages { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}
