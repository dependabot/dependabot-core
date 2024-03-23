using System.Collections.Immutable;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Discover;

internal static class SdkProjectDiscovery
{
    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverAsync(string repoRootPath, string workspacePath, string projectPath, Logger logger)
    {
        // Determine which targets and props files contribute to the build.
        var buildFiles = await MSBuildHelper.LoadBuildFilesAsync(repoRootPath, projectPath, includeSdkPropsAndTargets: true);

        // Get all the dependencies which are directly referenced from the project file or indirectly referenced from
        // targets and props files.
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles);

        var results = ImmutableArray.CreateBuilder<ProjectDiscoveryResult>();
        foreach (var buildFile in buildFiles)
        {
            // Only include build files that exist beneath the RepoRootPath.
            if (buildFile.IsOutsideBasePath)
            {
                continue;
            }

            // The build file dependencies have the correct DependencyType and the TopLevelDependencies have the evaluated version.
            // Combine them to have the set of dependencies that are directly referenced from the build file.
            var fileDependencies = BuildFile.GetDependencies(buildFile)
                .ToDictionary(d => d.Name, StringComparer.OrdinalIgnoreCase);
            var sdkDependencies = fileDependencies.Values
                .Where(d => d.Type == DependencyType.MSBuildSdk)
                .ToImmutableArray();
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
                var tfms = MSBuildHelper.GetTargetFrameworkMonikers(buildFiles)
                    .OrderBy(tfm => tfm)
                    .ToImmutableArray();
                var properties = MSBuildHelper.GetProperties(buildFiles).Values
                    .Where(p => !p.SourceFilePath.StartsWith(".."))
                    .OrderBy(p => p.Name)
                    .ToImmutableArray();
                var referencedProjectPaths = MSBuildHelper.GetProjectPathsFromProject(projectPath)
                    .Select(path => Path.GetRelativePath(workspacePath, path))
                    .OrderBy(p => p)
                    .ToImmutableArray();

                // Get the complete set of dependencies including transitive dependencies.
                directDependencies = directDependencies
                    .Select(d => d with { TargetFrameworks = tfms })
                    .ToImmutableArray();
                var transitiveDependencies = await GetTransitiveDependencies(repoRootPath, projectPath, tfms, directDependencies, logger);
                ImmutableArray<Dependency> dependencies = directDependencies.Concat(transitiveDependencies).Concat(sdkDependencies)
                    .OrderBy(d => d.Name)
                    .ToImmutableArray();

                results.Add(new()
                {
                    FilePath = Path.GetRelativePath(workspacePath, buildFile.Path),
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
                    FilePath = Path.GetRelativePath(workspacePath, buildFile.Path),
                    Dependencies = directDependencies.Concat(sdkDependencies)
                        .OrderBy(d => d.Name)
                        .ToImmutableArray(),
                });
            }
        }

        return results.ToImmutable();
    }

    private static async Task<ImmutableArray<Dependency>> GetTransitiveDependencies(string repoRootPath, string projectPath, ImmutableArray<string> tfms, ImmutableArray<Dependency> directDependencies, Logger logger)
    {
        Dictionary<string, Dependency> transitiveDependencies = new(StringComparer.OrdinalIgnoreCase);
        foreach (var tfm in tfms)
        {
            var tfmDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, projectPath, tfm, directDependencies, logger);
            foreach (var dependency in tfmDependencies.Where(d => d.IsTransitive))
            {
                if (!transitiveDependencies.TryGetValue(dependency.Name, out var existingDependency))
                {
                    transitiveDependencies[dependency.Name] = dependency;
                    continue;
                }

                transitiveDependencies[dependency.Name] = existingDependency with
                {
                    // Revisit this logic. We may want to return each dependency instead of merging them.
                    Version = SemanticVersion.Parse(existingDependency.Version!) > SemanticVersion.Parse(dependency.Version!)
                        ? existingDependency.Version
                        : dependency.Version,
                    TargetFrameworks = existingDependency.TargetFrameworks is not null && dependency.TargetFrameworks is not null
                        ? existingDependency.TargetFrameworks.Value.AddRange(dependency.TargetFrameworks)
                        : existingDependency.TargetFrameworks ?? dependency.TargetFrameworks,
                };
            }
        }

        return [.. transitiveDependencies.Values];
    }
}
