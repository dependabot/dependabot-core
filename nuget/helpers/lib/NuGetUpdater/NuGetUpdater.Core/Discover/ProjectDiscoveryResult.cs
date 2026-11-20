using System.Collections.Immutable;

using NuGet.Frameworks;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Discover;

public record ProjectDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsSuccess { get; init; } = true;
    public JobErrorBase? Error { get; init; } = null;
    public ImmutableArray<string> TargetFrameworks { get; init; } = [];
    public ImmutableDictionary<string, TargetFrameworkFallback> TargetFrameworkFallbacks { get; init; } = ImmutableDictionary<string, TargetFrameworkFallback>.Empty;
    public ImmutableDictionary<string, ImmutableDictionary<string, string>> CentralPackageVersions { get; init; } = ImmutableDictionary<string, ImmutableDictionary<string, string>>.Empty;
    public ImmutableDictionary<string, ImmutableDictionary<string, string>> PackageReferenceVersionOverrides { get; init; } = ImmutableDictionary<string, ImmutableDictionary<string, string>>.Empty;
    public PackageManagementKind PackageManagementKind { get; init; } = PackageManagementKind.Default;
    public string? PackageManagementSpecialFileRelativePath { get; init; } = null;
    public ImmutableArray<string> ReferencedProjectPaths { get; init; } = [];
    public required ImmutableArray<string> ImportedFiles { get; init; }
    public required ImmutableArray<string> AdditionalFiles { get; init; }
    public required ImmutableArray<Dependency> Dependencies { get; init; }
    public bool HasNoWarnNU1701 { get; init; } = false;
    /// <summary>
    /// Maps each package (keyed as "Name/Version") to its direct dependency package names, as extracted from project.assets.json.
    /// </summary>
    public ImmutableDictionary<string, ImmutableArray<string>> DependencyGraph { get; init; } = ImmutableDictionary<string, ImmutableArray<string>>.Empty;

    internal NuGetFramework GetFramework(string targetFramework)
    {
        var framework = NuGetFramework.Parse(targetFramework);
        if (!TargetFrameworkFallbacks.TryGetValue(targetFramework, out var fallback))
        {
            fallback = TargetFrameworkFallbacks.FirstOrDefault(entry =>
                NuGetFramework.Comparer.Equals(NuGetFramework.Parse(entry.Key), framework)).Value;
        }

        if (fallback is null || fallback.Imports.IsDefaultOrEmpty)
        {
            return framework;
        }

        var imports = fallback.Imports.Select(NuGetFramework.Parse).ToArray();
        return fallback.AssetTargetFallback
            ? new AssetTargetFallbackFramework(framework, imports)
            : new FallbackFramework(framework, imports);
    }

    internal ImmutableDictionary<string, string>? GetCentralPackageVersions(string targetFramework)
        => GetFrameworkVersions(CentralPackageVersions, targetFramework);

    internal ImmutableDictionary<string, string>? GetPackageReferenceVersionOverrides(string targetFramework)
        => GetFrameworkVersions(PackageReferenceVersionOverrides, targetFramework);

    private static ImmutableDictionary<string, string>? GetFrameworkVersions(
        ImmutableDictionary<string, ImmutableDictionary<string, string>> versionsByFramework,
        string targetFramework)
    {
        if (versionsByFramework.TryGetValue(targetFramework, out var versions))
        {
            return versions.WithComparers(StringComparer.OrdinalIgnoreCase);
        }

        var framework = NuGetFramework.Parse(targetFramework);
        return versionsByFramework.FirstOrDefault(entry =>
            NuGetFramework.Comparer.Equals(NuGetFramework.Parse(entry.Key), framework)).Value
            ?.WithComparers(StringComparer.OrdinalIgnoreCase);
    }
}
