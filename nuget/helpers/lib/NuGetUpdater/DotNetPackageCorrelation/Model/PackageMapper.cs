using Semver;

namespace DotNetPackageCorrelation;

public class PackageMapper
{
    public RuntimePackages RuntimePackages { get; }

    private PackageMapper(RuntimePackages runtimePackages)
    {
        RuntimePackages = runtimePackages;
    }

    /// <summary>
    /// Find the version of <paramref name="candidatePackageName"/> that shipped at the same time as
    /// &quot;<paramref name="packageName"/>/<paramref name="packageVersion"/>&quot;.
    /// </summary>
    public SemVersion? GetPackageVersionThatShippedWithOtherPackage(string packageName, SemVersion packageVersion, string candidatePackageName)
    {
        var runtimeVersion = GetRuntimeVersionFromPackage(packageName, packageVersion);
        if (runtimeVersion is null)
        {
            // no runtime found that contains the package
            return null;
        }

        var candidateRuntimeVersions = RuntimePackages.Runtimes.Keys
            .Where(v => v.Major == runtimeVersion.Major)
            .Where(v => v.ComparePrecedenceTo(runtimeVersion) <= 0)
            .OrderBy(v => v, SemVerComparer.Instance)
            .Reverse()
            .ToArray();
        foreach (var candidateRuntimeVersion in candidateRuntimeVersions)
        {
            if (!RuntimePackages.Runtimes.TryGetValue(candidateRuntimeVersion, out var packageSet))
            {
                continue;
            }

            if (packageSet.Packages.TryGetValue(candidatePackageName, out var foundPackageVersion))
            {
                return foundPackageVersion;
            }
        }

        return null;
    }

    private SemVersion? GetRuntimeVersionFromPackage(string packageName, SemVersion packageVersion)
    {
        // TODO: linear search is slow
        foreach (var runtime in RuntimePackages.Runtimes)
        {
            if (runtime.Value.Packages.TryGetValue(packageName, out var foundPackageVersion) &&
                foundPackageVersion == packageVersion)
            {
                return runtime.Key;
            }
        }

        return null;
    }

    public static PackageMapper Load(RuntimePackages runtimePackages)
    {
        return new PackageMapper(runtimePackages);
    }
}
