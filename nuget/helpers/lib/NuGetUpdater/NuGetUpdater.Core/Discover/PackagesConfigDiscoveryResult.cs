using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record PackagesConfigDiscoveryResult : IDiscoveryResultWithDependencies
{
    public required string FilePath { get; init; }
    public bool IsSuccess { get; init; } = true;
    public required ImmutableArray<Dependency> Dependencies { get; init; }
    public required ImmutableArray<string> TargetFrameworks { get; init; }
}
