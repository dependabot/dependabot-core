using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Discover;

public record ProjectDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public required ImmutableArray<Dependency> Dependencies { get; init; }
    public bool IsSuccess { get; init; } = true;
    public JobErrorBase? Error { get; init; } = null;
    public ImmutableArray<Property> Properties { get; init; } = [];
    public ImmutableArray<string> TargetFrameworks { get; init; } = [];
    public ImmutableArray<string> ReferencedProjectPaths { get; init; } = [];
    public required ImmutableArray<string> ImportedFiles { get; init; }
    public required ImmutableArray<string> AdditionalFiles { get; init; }
}
