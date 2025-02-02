using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

internal static class DotNetToolsJsonDiscovery
{
    public static DotNetToolsJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, ILogger logger)
    {
        if (!MSBuildHelper.TryGetDotNetToolsJsonPath(repoRootPath, workspacePath, out var dotnetToolsJsonPath))
        {
            logger.Info("  No dotnet-tools.json file found.");
            return null;
        }

        var dotnetToolsJsonFile = DotNetToolsJsonBuildFile.Open(workspacePath, dotnetToolsJsonPath, logger);

        logger.Info($"  Discovered [{dotnetToolsJsonFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(dotnetToolsJsonFile)
            .OrderBy(d => d.Name)
            .ToImmutableArray();

        return new()
        {
            FilePath = dotnetToolsJsonFile.RelativePath,
            IsSuccess = !dotnetToolsJsonFile.FailedToParse,
            Dependencies = dependencies,
        };
    }
}
