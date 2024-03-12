using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class GlobalJsonDiscovery
{
    public static GlobalJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, Logger logger)
    {
        var globalJsonFile = TryLoadBuildFile(repoRootPath, workspacePath, logger);
        if (globalJsonFile is null)
        {
            logger.Log("  No global.json file found.");
            return null;
        }

        logger.Log($"  Discovered [{globalJsonFile.RepoRelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(globalJsonFile);

        return new()
        {
            FilePath = globalJsonFile.RepoRelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }

    private static GlobalJsonBuildFile? TryLoadBuildFile(string repoRootPath, string workspacePath, Logger logger)
    {
        return MSBuildHelper.GetGlobalJsonPath(repoRootPath, workspacePath) is { } globalJsonPath
            ? GlobalJsonBuildFile.Open(repoRootPath, globalJsonPath, logger)
            : null;
    }
}
