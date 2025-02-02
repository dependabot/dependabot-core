using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public interface IDiscoveryResult
{
    string FilePath { get; }
    bool IsSuccess { get; }
}

public interface IDiscoveryResultWithDependencies : IDiscoveryResult
{
    ImmutableArray<Dependency> Dependencies { get; }
}
