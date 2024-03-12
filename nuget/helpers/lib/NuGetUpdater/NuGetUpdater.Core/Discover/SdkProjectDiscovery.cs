using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class SdkProjectDiscovery
{
    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverAsync(string repoRootPath, string projectPath, Logger logger)
    {
        // Determine which targets and props files contribute to the build.
        var buildFiles = await MSBuildHelper.LoadBuildFilesAsync(repoRootPath, projectPath);

        // Get all the dependencies which are directly referenced from the project file or indirectly referenced from
        // targets and props files.
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles);

        var results = ImmutableArray.CreateBuilder<ProjectDiscoveryResult>();
        foreach (var buildFile in buildFiles)
        {
            // The build file dependencies have the correct DependencyType and the TopLevelDependencies have the evaluated version.
            // Combine them to have the set of dependencies that are directly referenced from the build file.
            var fileDependencies = BuildFile.GetDependencies(buildFile)
                .ToDictionary(d => d.Name, StringComparer.OrdinalIgnoreCase);
            var directDependencies = topLevelDependencies
                .Where(d => fileDependencies.ContainsKey(d.Name))
                .Select(d =>
                {
                    var dependency = fileDependencies[d.Name];
                    return d with
                    {
                        Type = dependency.Type,
                        IsDirect = true
                    };
                }).ToImmutableArray();

            if (buildFile.GetFileType() == ProjectBuildFileType.Project)
            {
                // Collect information that is specific to the project file.
                var tfms = MSBuildHelper.GetTargetFrameworkMonikers(buildFiles).ToImmutableArray();
                var properties = MSBuildHelper.GetProperties(buildFiles).ToImmutableDictionary();
                var referencedProjectPaths = MSBuildHelper.GetProjectPathsFromProject(projectPath).ToImmutableArray();

                // Get the complete set of dependencies including transitive dependencies.
                var allDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, projectPath, tfms.First(), directDependencies, logger);
                var dependencies = directDependencies.Concat(allDependencies.Where(d => d.IsTransitive)).ToImmutableArray();

                results.Add(new()
                {
                    FilePath = buildFile.RepoRelativePath,
                    Properties = properties,
                    TargetFrameworks = tfms,
                    ReferencedProjectPaths = referencedProjectPaths,
                    Dependencies = dependencies,
                });
            }
            else
            {
                results.Add(new()
                {
                    FilePath = buildFile.RepoRelativePath,
                    Properties = ImmutableDictionary<string, string>.Empty,
                    Dependencies = directDependencies,
                });
            }
        }

        return results.ToImmutable();
    }
}
