using System;
using System.Linq;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

internal static class GlobalJsonUpdater
{
    public static async Task UpdateDependencyAsync(
        string repoRootPath,
        string workspacePath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        Logger logger)
    {
        var globalJsonFile = LoadBuildFile(repoRootPath, workspacePath, logger);
        if (globalJsonFile is null)
        {
            logger.Log("  No global.json files found.");
            return;
        }

        logger.Log($"  Updating [{globalJsonFile.RepoRelativePath}] file.");

        var containsDependency = globalJsonFile.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (!containsDependency)
        {
            logger.Log($"    Dependency [{dependencyName}] not found.");
            return;
        }

        if (globalJsonFile.MSBuildSdks?.TryGetPropertyValue(dependencyName, out var version) != true
            || version?.GetValue<string>() is not string versionString)
        {
            logger.Log("    Unable to determine dependency version.");
            return;
        }

        if (versionString != previousDependencyVersion)
        {
            return;
        }

        globalJsonFile.UpdateProperty(["msbuild-sdks", dependencyName], newDependencyVersion);

        if (await globalJsonFile.SaveAsync())
        {
            logger.Log($"    Saved [{globalJsonFile.RepoRelativePath}].");
        }
    }

    private static GlobalJsonBuildFile? LoadBuildFile(string repoRootPath, string workspacePath, Logger logger)
    {
        return MSBuildHelper.GetGlobalJsonPath(repoRootPath, workspacePath) is { } globalJsonPath
            ? GlobalJsonBuildFile.Open(repoRootPath, globalJsonPath, logger)
            : null;
    }
}
