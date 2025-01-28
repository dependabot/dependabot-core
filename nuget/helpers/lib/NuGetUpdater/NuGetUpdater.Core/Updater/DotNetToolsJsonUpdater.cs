namespace NuGetUpdater.Core;

internal static class DotNetToolsJsonUpdater
{
    public static async Task UpdateDependencyAsync(
        string repoRootPath,
        string workspacePath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        ILogger logger)
    {
        if (!MSBuildHelper.TryGetDotNetToolsJsonPath(repoRootPath, workspacePath, out var dotnetToolsJsonPath))
        {
            logger.Info("  No dotnet-tools.json file found.");
            return;
        }

        var dotnetToolsJsonFile = DotNetToolsJsonBuildFile.Open(repoRootPath, dotnetToolsJsonPath, logger);

        logger.Info($"  Updating [{dotnetToolsJsonFile.RelativePath}] file.");

        var containsDependency = dotnetToolsJsonFile.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (!containsDependency)
        {
            logger.Info($"    Dependency [{dependencyName}] not found.");
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
                logger.Info($"    Saved [{dotnetToolsJsonFile.RelativePath}].");
            }
        }
    }
}
