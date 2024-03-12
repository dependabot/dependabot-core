namespace NuGetUpdater.Core;

internal static class DotNetToolsJsonUpdater
{
    public static async Task UpdateDependencyAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion,
        Logger logger)
    {
        var dotnetToolsJsonFile = TryLoadBuildFile(repoRootPath, workspacePath, logger);
        if (dotnetToolsJsonFile is null)
        {
            logger.Log("  No dotnet-tools.json file found.");
            return;
        }

        logger.Log($"  Updating [{dotnetToolsJsonFile.RepoRelativePath}] file.");

        var containsDependency = dotnetToolsJsonFile.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (!containsDependency)
        {
            logger.Log($"    Dependency [{dependencyName}] not found.");
            return;
        }

        var tool = dotnetToolsJsonFile.Tools
            .Single(kvp => kvp.Key.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));

        var toolObject = tool.Value?.AsObject();

        if (toolObject is not null &&
            toolObject["version"]?.GetValue<string>() == previousDependencyVersion)
        {
            dotnetToolsJsonFile.UpdateProperty(["tools", dependencyName, "version"], newDependencyVersion);

            if (await dotnetToolsJsonFile.SaveAsync())
            {
                logger.Log($"    Saved [{dotnetToolsJsonFile.RepoRelativePath}].");
            }
        }
    }

    private static DotNetToolsJsonBuildFile? TryLoadBuildFile(string repoRootPath, string workspacePath, Logger logger)
    {
        return MSBuildHelper.GetDotNetToolsJsonPath(repoRootPath, workspacePath) is { } dotnetToolsJsonPath
            ? DotNetToolsJsonBuildFile.Open(repoRootPath, dotnetToolsJsonPath, logger)
            : null;
    }
}
