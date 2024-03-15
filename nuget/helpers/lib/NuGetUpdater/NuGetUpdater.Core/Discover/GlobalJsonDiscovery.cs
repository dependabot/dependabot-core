using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class GlobalJsonDiscovery
{
    public static GlobalJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, Logger logger)
    {
        if (!MSBuildHelper.TryGetGlobalJsonPath(repoRootPath, workspacePath, out var globalJsonPath))
        {
            logger.Log("  No global.json file found.");
            return null;
        }

        var globalJsonFile = GlobalJsonBuildFile.Open(workspacePath, globalJsonPath, logger);

        logger.Log($"  Discovered [{globalJsonFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(globalJsonFile);

        return new()
        {
            FilePath = globalJsonFile.RelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }
}
