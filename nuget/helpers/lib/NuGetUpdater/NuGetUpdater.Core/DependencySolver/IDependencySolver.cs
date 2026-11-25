using System.Collections.Immutable;

using NuGet.Frameworks;

namespace NuGetUpdater.Core.DependencySolver;

public interface IDependencySolver
{
    Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, NuGetFramework targetFramework);
}
