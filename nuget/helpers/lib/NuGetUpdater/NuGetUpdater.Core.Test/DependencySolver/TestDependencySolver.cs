using System.Collections.Immutable;

using NuGetUpdater.Core.DependencySolver;

namespace NuGetUpdater.Core.Test.DependencySolver;

public class TestDependencySolver : IDependencySolver
{
    public readonly Func<ImmutableArray<Dependency>, ImmutableArray<Dependency>, string, Task<ImmutableArray<Dependency>?>> SolveFunc;

    public TestDependencySolver(Func<ImmutableArray<Dependency>, ImmutableArray<Dependency>, string, Task<ImmutableArray<Dependency>?>> solveFunc)
    {
        SolveFunc = solveFunc;
    }

    public Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, string targetFramework)
    {
        return SolveFunc(existingTopLevelDependencies, desiredDependencies, targetFramework);
    }

    public static TestDependencySolver Identity()
    {
        return new TestDependencySolver((existing, desired, _) =>
        {
            return Task.FromResult<ImmutableArray<Dependency>?>(desired);
        });
    }
}
