using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal static class DependencyFinder
{
    public static async Task<ImmutableDictionary<NuGetFramework, ImmutableArray<Dependency>>> GetDependenciesAsync(
        string workspacePath,
        string projectPath,
        IEnumerable<NuGetFramework> frameworks,
        ImmutableHashSet<string> packageIds,
        NuGetVersion version,
        Logger logger)
    {
        var versionString = version.ToNormalizedString();
        var packages = packageIds
            .Select(id => new Dependency(id, versionString, DependencyType.Unknown))
            .ToImmutableArray();

        var result = ImmutableDictionary.CreateBuilder<NuGetFramework, ImmutableArray<Dependency>>();
        foreach (var framework in frameworks)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                workspacePath,
                projectPath,
                framework.ToString(),
                packages,
                logger);
            result.Add(framework, [.. dependencies.Select(d => d with { IsTransitive = false })]);
        }
        return result.ToImmutable();
    }
}
