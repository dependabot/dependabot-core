using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class PackagesConfigDiscovery
{
    public static PackagesConfigDiscoveryResult? Discover(string workspacePath, string projectPath, Logger logger)
    {
        if (!NuGetHelper.TryGetPackagesConfigFile(projectPath, out var packagesConfigPath))
        {
            logger.Log("  No packages.config file found.");
            return null;
        }

        var packagesConfigFile = PackagesConfigBuildFile.Open(workspacePath, packagesConfigPath);

        logger.Log($"  Discovered [{packagesConfigFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(packagesConfigFile);

        return new()
        {
            FilePath = packagesConfigFile.RelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }
}
