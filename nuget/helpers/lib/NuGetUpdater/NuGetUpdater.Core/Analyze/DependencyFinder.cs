using System.Collections.Immutable;

using NuGet.Frameworks;

namespace NuGetUpdater.Core.Analyze;

internal static class DependencyFinder
{
    public static async Task<ImmutableDictionary<NuGetFramework, ImmutableArray<Dependency>>> GetDependenciesAsync(
        string workspacePath,
        string projectPath,
        IEnumerable<NuGetFramework> frameworks,
        Dependency package,
        Logger logger)
    {
        var result = ImmutableDictionary.CreateBuilder<NuGetFramework, ImmutableArray<Dependency>>();
        foreach (var framework in frameworks)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                workspacePath,
                projectPath,
                framework.ToString(),
                [package],
                logger);
            result.Add(framework, [.. dependencies.Select(d => d with { IsTransitive = false })]);
        }
        return result.ToImmutable();
    }
}
