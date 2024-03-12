using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record DirectoryPackagesPropsDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsTransitivePinningEnabled { get; init; }
    public ImmutableArray<Dependency> Dependencies { get; init; }
}
