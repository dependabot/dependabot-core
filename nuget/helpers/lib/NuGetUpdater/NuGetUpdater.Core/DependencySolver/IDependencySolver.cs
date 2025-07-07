using System.Collections.Immutable;

namespace NuGetUpdater.Core.DependencySolver;

public interface IDependencySolver
{
    Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, string targetFramework);
}
