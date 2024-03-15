using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class DotNetToolsJsonDiscovery
{
    public static DotNetToolsJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, Logger logger)
    {
        if (!MSBuildHelper.TryGetDotNetToolsJsonPath(repoRootPath, workspacePath, out var dotnetToolsJsonPath))
        {
            logger.Log("  No dotnet-tools.json file found.");
            return null;
        }

        var dotnetToolsJsonFile = DotNetToolsJsonBuildFile.Open(workspacePath, dotnetToolsJsonPath, logger);

        logger.Log($"  Discovered [{dotnetToolsJsonFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(dotnetToolsJsonFile);

        return new()
        {
            FilePath = dotnetToolsJsonFile.RelativePath,
            Dependencies = dependencies.ToImmutableArray(),
        };
    }
}
