using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Discover;

public record ProjectDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsSuccess { get; init; } = true;
    public JobErrorBase? Error { get; init; } = null;
    public ImmutableArray<string> TargetFrameworks { get; init; } = [];
    public PackageManagementKind PackageManagementKind { get; init; } = PackageManagementKind.Default;
    public string? PackageManagementSpecialFileRelativePath { get; init; } = null;
    public ImmutableArray<string> ReferencedProjectPaths { get; init; } = [];
    public required ImmutableArray<string> ImportedFiles { get; init; }
    public required ImmutableArray<string> AdditionalFiles { get; init; }
    public required ImmutableArray<Dependency> Dependencies { get; init; }
    public bool CentralPackageTransitivePinningEnabled { get; init; } = false;

    /// <summary>
    /// Maps each package (keyed as "Name/Version") to its direct dependency package names, as extracted from project.assets.json.
    /// </summary>
    public ImmutableDictionary<string, ImmutableArray<string>> DependencyGraph { get; init; } = ImmutableDictionary<string, ImmutableArray<string>>.Empty;
}
