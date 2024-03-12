using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record PackagesConfigDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public ImmutableArray<Dependency> Dependencies { get; init; }
}
