using System.Collections.Immutable;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

internal static class PackagesConfigDiscovery
{
    public static async Task<PackagesConfigDiscoveryResult?> Discover(string repoRootPath, string workspacePath, string projectPath, ExperimentsManager experimentsManager, ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(projectPath, ProjectHelper.PathFormat.Full);
        var packagesConfigPath = additionalFiles.FirstOrDefault(p => Path.GetFileName(p).Equals(ProjectHelper.PackagesConfigFileName, StringComparison.Ordinal));

        if (packagesConfigPath is null)
        {
            logger.Info("  No packages.config file found.");
            return null;
        }

        var packagesConfigFile = PackagesConfigBuildFile.Open(workspacePath, packagesConfigPath);

        logger.Info($"  Discovered [{packagesConfigFile.RelativePath}] file.");

        var dependencies = BuildFile.GetDependencies(packagesConfigFile)
            .OrderBy(d => d.Name)
            .ToImmutableArray();

        // generate `$(TargetFramework)` via MSBuild
        var tfms = await MSBuildHelper.GetTargetFrameworkValuesFromProject(repoRootPath, projectPath, experimentsManager, logger);

        var additionalFilesRelative = additionalFiles.Select(p => Path.GetRelativePath(projectDirectory, p).NormalizePathToUnix()).ToImmutableArray();
        return new()
        {
            FilePath = packagesConfigFile.RelativePath,
            Dependencies = dependencies.Select(d => d with { TargetFrameworks = tfms }).ToImmutableArray(),
            TargetFrameworks = tfms,
            AdditionalFiles = additionalFilesRelative,
        };
    }
}
