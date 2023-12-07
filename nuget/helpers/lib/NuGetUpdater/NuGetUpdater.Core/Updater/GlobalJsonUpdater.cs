using System;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

internal static partial class GlobalJsonUpdater
{
    public static async Task UpdateDependencyAsync(string repoRootPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, Logger logger)
    {
        var buildFiles = LoadBuildFiles(repoRootPath);
        if (buildFiles.Length == 0)
        {
            logger.Log($"  No global.json files found.");
            return;
        }

        logger.Log($"  Updating global.json files.");


        var filesToUpdate = buildFiles.Where(f =>
            f.GetDependencies().Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase)))
            .ToImmutableArray();
        if (filesToUpdate.Length == 0)
        {
            logger.Log($"    Dependency [{dependencyName}] not found in any global.json files.");
            return;
        }

        foreach (var buildFile in filesToUpdate)
        {
            if (buildFile.MSBuildSdks?.TryGetPropertyValue(dependencyName, out var version) != true)
            {
                continue;
            }

            if (version?.GetValue<string>() == previousDependencyVersion)
            {
                buildFile.UpdateProperty(new[] { "msbuild-sdks", dependencyName }, newDependencyVersion);

                if (await buildFile.SaveAsync())
                {
                    logger.Log($"    Saved [{buildFile.RepoRelativePath}].");
                }
            }
        }
    }

    private static ImmutableArray<GlobalJsonBuildFile> LoadBuildFiles(string repoRootPath)
    {
        var options = new EnumerationOptions()
        {
            RecurseSubdirectories = true,
            MatchType = MatchType.Win32,
            AttributesToSkip = 0,
            IgnoreInaccessible = false,
            MatchCasing = MatchCasing.CaseInsensitive,
        };
        return Directory.EnumerateFiles(repoRootPath, "global.json", options)
            .Select(path => GlobalJsonBuildFile.Open(repoRootPath, path))
            .ToImmutableArray();
    }
}
