using System.Collections.Immutable;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal static class DependencyFinder
{
    public static async Task<ImmutableDictionary<string, ImmutableArray<Dependency>>> GetDependenciesAsync(
        string repoRoot,
        string projectPath,
        IEnumerable<string> frameworks,
        ImmutableHashSet<string> packageIds,
        NuGetVersion version,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versionString = version.ToNormalizedString();
        var packages = packageIds
            .Select(id => new Dependency(id, versionString, DependencyType.Unknown))
            .ToImmutableArray();

        var result = ImmutableDictionary.CreateBuilder<string, ImmutableArray<Dependency>>();
        foreach (var framework in frameworks)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                repoRoot,
                projectPath,
                framework,
                packages,
                logger);
            var updatedDependencies = new Dependency[dependencies.Length];
            await Parallel.ForEachAsync(
                Enumerable.Range(0, dependencies.Length),
                new ParallelOptions { MaxDegreeOfParallelism = 4, CancellationToken = cancellationToken },
                async (index, token) =>
                {
                    var dependency = dependencies[index];
                    var infoUrl = await nugetContext.GetPackageInfoUrlAsync(dependency.Name, dependency.Version!, token);
                    updatedDependencies[index] = dependency with { IsTopLevel = true, InfoUrl = infoUrl };
                });

            result.Add(framework, updatedDependencies.ToImmutableArray());
        }

        return result.ToImmutable();
    }
}
