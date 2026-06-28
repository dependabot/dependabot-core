using System.Collections.Immutable;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Discover;

internal static class GlobalJsonDiscovery
{
    public static GlobalJsonDiscoveryResult? Discover(string repoRootPath, string workspacePath, ILogger logger)
    {
        if (!MSBuildHelper.TryGetGlobalJsonPath(repoRootPath, workspacePath, out var globalJsonPath))
        {
            logger.Info("  No global.json file found.");
            return null;
        }

        var globalJsonFile = GlobalJsonBuildFile.Open(workspacePath, globalJsonPath, logger);

        logger.Info($"  Discovered [{globalJsonFile.RelativePath}] file.");

        var allDependencies = BuildFile.GetDependencies(globalJsonFile)
            .OrderBy(d => d.Name)
            .ToImmutableArray();

        var dependencies = ImmutableArray.CreateBuilder<Dependency>();
        foreach (var dependency in allDependencies)
        {
            if (NuGetVersion.TryParse(dependency.Version, out _))
            {
                dependencies.Add(dependency);
            }
            else
            {
                logger.Warn($"  Dependency '{dependency.Name}' has an unparseable version: '{dependency.Version}' and will be ignored.");
            }
        }

        return new()
        {
            FilePath = globalJsonFile.RelativePath,
            IsSuccess = !globalJsonFile.FailedToParse,
            Dependencies = dependencies.ToImmutable(),
        };
    }
}
