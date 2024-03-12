using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Test.Discover;

public record ExpectedWorkspaceDiscoveryResult : IDiscoveryResult
{
    public required string FilePath { get; init; }
    public WorkspaceType Type { get; init; }
    public ImmutableArray<string> TargetFrameworks { get; init; }
    public ImmutableArray<ExpectedSdkProjectDiscoveryResult> Projects { get; init; }
    public int? ExpectedProjectCount { get; init; }
    public DirectoryPackagesPropsDiscoveryResult? DirectoryPackagesProps { get; init; }
    public GlobalJsonDiscoveryResult? GlobalJson { get; init; }
    public DotNetToolsJsonDiscoveryResult? DotNetToolsJson { get; init; }
}

public record ExpectedSdkProjectDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public required ImmutableDictionary<string, string> Properties { get; init; }
    public ImmutableArray<string> TargetFrameworks { get; init; }
    public ImmutableArray<string> ReferencedProjectPaths { get; init; }
    public ImmutableArray<Dependency> Dependencies { get; init; }
    public int? ExpectedDependencyCount { get; init; }
}
