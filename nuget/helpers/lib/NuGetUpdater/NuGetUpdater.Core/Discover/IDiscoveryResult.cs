using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public interface IDiscoveryResult
{
    string FilePath { get; }
}

public interface IDiscoveryResultWithDependencies : IDiscoveryResult
{
    ImmutableArray<Dependency> Dependencies { get; }
}
