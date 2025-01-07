using System.Collections.Immutable;

using Semver;

namespace DotNetPackageCorrelation;

public static class SdkPackagesExtensions
{
    public static SemVersion? GetReplacementPackageVersion(this SdkPackages packages, SemVersion sdkVersion, string packageName)
    {
        var sdkVersionsToCheck = packages.Packages.Keys
            .Where(v => v.Major == sdkVersion.Major)
            .Where(v => v.ComparePrecedenceTo(sdkVersion) <= 0)
            .OrderBy(v => v, SemVerComparer.Instance)
            .Reverse()
            .ToImmutableArray();
        foreach (var sdkVersionToCheck in sdkVersionsToCheck)
        {
            var sdkPackages = packages.Packages[sdkVersionToCheck];
            if (sdkPackages.Packages.TryGetValue(packageName, out var packageVersion))
            {
                return packageVersion;
            }
        }

        return null;
    }
}
