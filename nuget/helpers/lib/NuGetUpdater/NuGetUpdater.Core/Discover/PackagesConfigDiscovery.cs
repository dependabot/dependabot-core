using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class PackagesConfigDiscovery
{
    public static PackagesConfigDiscoveryResult? Discover(string repoRootPath, string workspacePath, Logger logger)
    {
        var packagesConfigFile = TryLoadBuildFile(repoRootPath, workspacePath, logger);
        if (packagesConfigFile is null)
        {
            logger.Log("  No packages.config file found.");
            return null;
        }

        logger.Log($"  Discovered [{packagesConfigFile.RepoRelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(packagesConfigFile);

        return new()
        {
            FilePath = packagesConfigFile.RepoRelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }

    private static PackagesConfigBuildFile? TryLoadBuildFile(string repoRootPath, string projectPath, Logger logger)
    {
        return NuGetHelper.HasPackagesConfigFile(projectPath, out var packagesConfigPath)
            ? PackagesConfigBuildFile.Open(repoRootPath, packagesConfigPath)
            : null;
    }
}
