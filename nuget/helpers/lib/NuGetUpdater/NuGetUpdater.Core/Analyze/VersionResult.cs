using System.Collections.Immutable;

using NuGet.Configuration;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal class VersionResult
{
    private readonly Dictionary<NuGetVersion, List<PackageSource>> _versions = [];
    private readonly List<PackageSource> _currentVersionSources = [];

    public NuGetVersion CurrentVersion { get; }

    public VersionResult(NuGetVersion currentVersion)
    {
        CurrentVersion = currentVersion;
    }

    public void AddCurrentVersionSource(PackageSource source)
    {
        _currentVersionSources.Add(source);
    }

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
        if (version == CurrentVersion)
        {
            return [.. _currentVersionSources];
        }

        return [.. _versions[version]];
    }

    public ImmutableArray<NuGetVersion> GetVersions()
    {
        return [.. _versions.Keys];
    }
}
