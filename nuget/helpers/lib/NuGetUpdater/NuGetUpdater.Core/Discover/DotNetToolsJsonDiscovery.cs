using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class DotNetToolsJsonDiscovery
{
    public static DotNetToolsJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, Logger logger)
    {
        var dotnetToolsJsonFile = TryLoadBuildFile(repoRootPath, workspacePath, logger);
        if (dotnetToolsJsonFile is null)
        {
            logger.Log("  No dotnet-tools.json file found.");
            return null;
        }

        logger.Log($"  Discovered [{dotnetToolsJsonFile.RepoRelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(dotnetToolsJsonFile);

        return new()
        {
            FilePath = dotnetToolsJsonFile.RepoRelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }

    private static DotNetToolsJsonBuildFile? TryLoadBuildFile(string repoRootPath, string workspacePath, Logger logger)
    {
        return MSBuildHelper.GetDotNetToolsJsonPath(repoRootPath, workspacePath) is { } dotnetToolsJsonPath
            ? DotNetToolsJsonBuildFile.Open(repoRootPath, dotnetToolsJsonPath, logger)
            : null;
    }
}
