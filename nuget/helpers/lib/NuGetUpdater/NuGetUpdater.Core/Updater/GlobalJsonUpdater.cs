namespace NuGetUpdater.Core;

internal static class GlobalJsonUpdater
{
    public static async Task<string?> UpdateDependencyAsync(
        string repoRootPath,
        string workspacePath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        ILogger logger)
    {
        if (!MSBuildHelper.TryGetGlobalJsonPath(repoRootPath, workspacePath, out var globalJsonPath))
        {
            logger.Info("  No global.json file found.");
            return null;
        }

        var globalJsonFile = GlobalJsonBuildFile.Open(repoRootPath, globalJsonPath, logger);

        logger.Info($"  Updating [{globalJsonFile.RelativePath}] file.");

        var containsDependency = globalJsonFile.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (!containsDependency)
        {
            logger.Info($"    Dependency [{dependencyName}] not found.");
            return null;
        }

        if (globalJsonFile.MSBuildSdks?.TryGetPropertyValue(dependencyName, out var version) != true
            || version?.GetValue<string>() is not string versionString)
        {
            logger.Info("    Unable to determine dependency version.");
            return null;
        }

        if (versionString != previousDependencyVersion)
        {
            logger.Info($"    Expected old version of {previousDependencyVersion} but found {versionString}.");
            return null;
        }

        globalJsonFile.UpdateProperty(["msbuild-sdks", dependencyName], newDependencyVersion);

        if (await globalJsonFile.SaveAsync())
        {
            logger.Info($"    Saved [{globalJsonFile.RelativePath}].");
            return globalJsonFile.Path;
        }

        return null;
    }
}
