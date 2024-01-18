using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

internal static partial class DotNetToolsJsonUpdater
{
    public static async Task UpdateDependencyAsync(string repoRootPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, Logger logger)
    {
        var buildFiles = LoadBuildFiles(repoRootPath, logger);
        if (buildFiles.Length == 0)
        {
            logger.Log($"  No dotnet-tools.json files found.");
            return;
        }

        logger.Log($"  Updating dotnet-tools.json files.");


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
                buildFile.UpdateProperty(new[] { "tools", dependencyName, "version" }, newDependencyVersion);

                if (await buildFile.SaveAsync())
                {
                    logger.Log($"    Saved [{buildFile.RepoRelativePath}].");
                }
            }
        }
    }

    private static ImmutableArray<DotNetToolsJsonBuildFile> LoadBuildFiles(string repoRootPath, Logger logger)
    {
        var options = new EnumerationOptions()
        {
            RecurseSubdirectories = true,
            MatchType = MatchType.Win32,
            AttributesToSkip = 0,
            IgnoreInaccessible = false,
            MatchCasing = MatchCasing.CaseInsensitive,
        };
        return Directory.EnumerateFiles(repoRootPath, "dotnet-tools.json", options)
            .Select(path => DotNetToolsJsonBuildFile.Open(repoRootPath, path, logger))
            .ToImmutableArray();
    }
}
