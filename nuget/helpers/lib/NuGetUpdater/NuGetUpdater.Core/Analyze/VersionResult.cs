using System.Collections.Immutable;

using NuGet.Configuration;
using NuGet.Versioning;

namespace NuGetUpdater.Analyzer;

internal class VersionResult
{
    private readonly Dictionary<NuGetVersion, List<PackageSource>> _versions = new();

    public void AddRange(PackageSource source, IEnumerable<NuGetVersion> versions)
    {
        foreach (var version in versions)
        {
            if (_versions.ContainsKey(version))
            {
                _versions[version].Add(source);
            }
            else
            {
                _versions.Add(version, [source]);
            }
        }
    }

    public ImmutableArray<PackageSource> GetPackageSources(NuGetVersion version)
    {
        return [.. _versions[version]];
    }

    public ImmutableArray<NuGetVersion> GetVersions()
    {
        return [.. _versions.Keys];
    }
}
