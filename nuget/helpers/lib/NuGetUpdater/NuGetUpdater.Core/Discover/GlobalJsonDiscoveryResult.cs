using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record GlobalJsonDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsSuccess { get; init; } = true;
    public ImmutableArray<Dependency> Dependencies { get; init; }
}
