using System;
using System.Collections.Immutable;
using System.Linq;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

internal static class DotNetToolsJsonUpdater
{
    public static async Task UpdateDependencyAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion,
        Logger logger)
    {
        var buildFiles = LoadBuildFiles(repoRootPath, workspacePath, logger);
        if (buildFiles.Length == 0)
        {
            logger.Log("  No dotnet-tools.json files found.");
            return;
        }

        logger.Log("  Updating dotnet-tools.json files.");


        var filesToUpdate = buildFiles.Where(f =>
                f.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase)))
            .ToImmutableArray();
        if (filesToUpdate.Length == 0)
        {
            logger.Log($"    Dependency [{dependencyName}] not found in any dotnet-tools.json files.");
            return;
        }

        foreach (var buildFile in filesToUpdate)
        {
            var tool = buildFile.Tools
                .Single(kvp => kvp.Key.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));

            var toolObject = tool.Value?.AsObject();

            if (toolObject is not null &&
                toolObject["version"]?.GetValue<string>() == previousDependencyVersion)
            {
                buildFile.UpdateProperty(["tools", dependencyName, "version"], newDependencyVersion);

                if (await buildFile.SaveAsync())
                {
                    logger.Log($"    Saved [{buildFile.RepoRelativePath}].");
                }
            }
        }
    }

    private static ImmutableArray<DotNetToolsJsonBuildFile> LoadBuildFiles(string repoRootPath, string workspacePath, Logger logger)
    {
        var dotnetToolsJsonPath = PathHelper.GetFileInDirectoryOrParent(workspacePath, repoRootPath, "./.config/dotnet-tools.json");
        return dotnetToolsJsonPath is not null
            ? [DotNetToolsJsonBuildFile.Open(repoRootPath, dotnetToolsJsonPath, logger)]
            : [];
    }
}
