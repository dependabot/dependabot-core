using Semver;

namespace DotNetPackageCorrelation;

public record SdkPackages
{
    public SortedDictionary<SemVersion, PackageSet> Packages { get; init; } = new(new SemVerComparer());
}
