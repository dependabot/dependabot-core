using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Test.Discover;

public record ExpectedWorkspaceDiscoveryResult : NativeResult
{
    public required string Path { get; init; }
    public bool IsSuccess { get; init; } = true;
    public ImmutableArray<ExpectedSdkProjectDiscoveryResult> Projects { get; init; }
    public int? ExpectedProjectCount { get; init; }
    public ExpectedDependencyDiscoveryResult? GlobalJson { get; init; }
    public ExpectedDependencyDiscoveryResult? DotNetToolsJson { get; init; }
}

public record ExpectedSdkProjectDiscoveryResult : ExpectedDependencyDiscoveryResult
{
    public required ImmutableArray<Property> Properties { get; init; }
    public required ImmutableArray<string> TargetFrameworks { get; init; }
    public required ImmutableArray<string> ReferencedProjectPaths { get; init; }
    public required ImmutableArray<string> ImportedFiles { get; init; }
    public required ImmutableArray<string> AdditionalFiles { get; init; }
}

public record ExpectedDependencyDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsSuccess { get; init; } = true;
    public ImmutableArray<Dependency> Dependencies { get; init; }
    public int? ExpectedDependencyCount { get; init; }
}
