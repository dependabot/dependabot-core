using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class PackagesConfigDiscovery
{
    public static async Task<PackagesConfigDiscoveryResult?> Discover(string repoRootPath, string workspacePath, string projectPath, ILogger logger)
    {
        if (!NuGetHelper.TryGetPackagesConfigFile(projectPath, out var packagesConfigPath))
        {
            logger.Log("  No packages.config file found.");
            return null;
        }

        var packagesConfigFile = PackagesConfigBuildFile.Open(workspacePath, packagesConfigPath);

        logger.Log($"  Discovered [{packagesConfigFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(packagesConfigFile)
            .OrderBy(d => d.Name)
            .ToImmutableArray();

        // generate `$(TargetFramework)` via MSBuild
        var tfms = await MSBuildHelper.GetTargetFrameworkValuesFromProject(repoRootPath, projectPath, logger);

        return new()
        {
            FilePath = packagesConfigFile.RelativePath,
            Dependencies = dependencies.Select(d => d with { TargetFrameworks = tfms }).ToImmutableArray(),
            TargetFrameworks = tfms,
        };
    }
}
