using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal static class DependencyFinder
{
    public static async Task<ImmutableDictionary<NuGetFramework, ImmutableArray<Dependency>>> GetDependenciesAsync(
        string repoRoot,
        string projectPath,
        IEnumerable<NuGetFramework> frameworks,
        ImmutableHashSet<string> packageIds,
        NuGetVersion version,
        NuGetContext nugetContext,
        ExperimentsManager experimentsManager,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versionString = version.ToNormalizedString();
        var packages = packageIds
            .Select(id => new Dependency(id, versionString, DependencyType.Unknown))
            .ToImmutableArray();

        var result = ImmutableDictionary.CreateBuilder<NuGetFramework, ImmutableArray<Dependency>>();
        foreach (var framework in frameworks)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                repoRoot,
                projectPath,
                framework.ToString(),
                packages,
                experimentsManager,
                logger);
            var updatedDependencies = new List<Dependency>();
            foreach (var dependency in dependencies)
            {
                var infoUrl = await nugetContext.GetPackageInfoUrlAsync(dependency.Name, dependency.Version!, cancellationToken);
                var updatedDependency = dependency with { IsTransitive = false, InfoUrl = infoUrl };
                updatedDependencies.Add(updatedDependency);
            }

            result.Add(framework, updatedDependencies.ToImmutableArray());
        }

        return result.ToImmutable();
    }
}
