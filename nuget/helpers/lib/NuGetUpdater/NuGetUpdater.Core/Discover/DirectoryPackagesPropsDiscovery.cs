using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class DirectoryPackagesPropsDiscovery
{
    public static DirectoryPackagesPropsDiscoveryResult? Discover(string repoRootPath, string workspacePath, ImmutableArray<ProjectDiscoveryResult> projectResults, Logger logger)
    {
        var projectResult = projectResults.FirstOrDefault(
            p => p.Properties.FirstOrDefault(prop => prop.Name.Equals("ManagePackageVersionsCentrally", StringComparison.OrdinalIgnoreCase)) is Property property
                && string.Equals(property.Value, "true", StringComparison.OrdinalIgnoreCase));
        if (projectResult is null)
        {
            logger.Log("  Central Package Management is not enabled.");
            return null;
        }
        else {
            logger.Log("  Central Package Management is enabled.");
        }

        var projectFilePath = Path.GetFullPath(projectResult.FilePath, workspacePath);
        if (!MSBuildHelper.TryGetDirectoryPackagesPropsPath(repoRootPath, projectFilePath, out var directoryPackagesPropsPath))
        {
            logger.Log("  No Directory.Packages.props file found.");
            return null;
        }

        var relativeDirectoryPackagesPropsPath = Path.GetRelativePath(workspacePath, directoryPackagesPropsPath);
        var directoryPackagesPropsFile = projectResults.FirstOrDefault(p => p.FilePath.Equals(relativeDirectoryPackagesPropsPath, StringComparison.OrdinalIgnoreCase));
        if (directoryPackagesPropsFile is null)
        {
            logger.Log($"  No project file found for [{relativeDirectoryPackagesPropsPath}].");
            return null;
        }

        logger.Log($"  Discovered [{directoryPackagesPropsFile.FilePath}] file.");

        var isTransitivePinningEnabled = projectResult.Properties.FirstOrDefault(prop => prop.Name.Equals("EnableTransitivePinning", StringComparison.OrdinalIgnoreCase)) is Property property
            && string.Equals(property.Value, "true", StringComparison.OrdinalIgnoreCase);
        var properties = projectResult.Properties.ToImmutableDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);
        var dependencies = GetDependencies(workspacePath, directoryPackagesPropsPath, properties)
            .OrderBy(d => d.Name)
            .ToImmutableArray();

        return new()
        {
            FilePath = directoryPackagesPropsFile.FilePath,
            IsTransitivePinningEnabled = isTransitivePinningEnabled,
            Dependencies = dependencies,
        };
    }

    private static IEnumerable<Dependency> GetDependencies(string workspacePath, string directoryPackagesPropsPath, ImmutableDictionary<string, Property> properties)
    {
        var dependencies = ProjectBuildFile.Open(workspacePath, directoryPackagesPropsPath).GetDependencies();
        return dependencies.Select(d =>
        {
            if (d.Version == null)
            {
                return d;
            }

            var evaluation = MSBuildHelper.GetEvaluatedValue(d.Version, properties);
            return d with
            {
                Version = evaluation.EvaluatedValue,
                EvaluationResult = evaluation,
                IsDirect = true,
            };
        });
    }
}
