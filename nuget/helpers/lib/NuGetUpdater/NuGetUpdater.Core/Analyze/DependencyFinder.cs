using System.Collections.Immutable;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal static class DependencyFinder
{
    public static async Task<ImmutableDictionary<string, ImmutableArray<Dependency>>> GetDependenciesAsync(
        string repoRoot,
        string projectPath,
        IEnumerable<string> frameworks,
        ImmutableArray<Dependency> packageTemplates,
        NuGetVersion version,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versionString = version.ToNormalizedString();
        var packages = packageTemplates
            .Select(dependency => dependency with
            {
                Version = versionString,
                Type = DependencyType.Unknown,
                IsTopLevel = true,
            })
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
            var updatedDependencies = new List<Dependency>();
            foreach (var dependency in dependencies)
            {
                var infoUrl = await nugetContext.GetPackageInfoUrlAsync(dependency.Name, dependency.Version!, cancellationToken);
                var updatedDependency = dependency with { IsTopLevel = true, InfoUrl = infoUrl };
                updatedDependencies.Add(updatedDependency);
            }

            result.Add(framework, updatedDependencies.ToImmutableArray());
        }

        return result.ToImmutable();
    }
}
