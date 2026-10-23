using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        ILogger logger)
    {
        // a plain restore only rewrites the lock file if it's no longer consistent with the project; locked mode would instead fail with NU1004
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        var (exitCode, stdout, stderr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", "-p:RestoreLockedMode=false", "-p:EnableWindowsTargeting=true", projectPath], projectDirectory);
        if (exitCode != 0)
        {
            logger.Error($"      Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
        }
    }

    /// <summary>
    /// Updates the lock file of every project in the workspace that depends on an updated package.  The update itself only restores the
    /// projects it modified and the projects they reference, so projects that only reach the package through a `&lt;ProjectReference&gt;`
    /// would otherwise keep a stale lock file.
    /// </summary>
    public static async Task UpdateLockFilesOfAffectedProjectsAsync(
        DirectoryInfo repoContentsPath,
        WorkspaceDiscoveryResult discoveryResult,
        IEnumerable<UpdateOperationBase> updateOperations,
        ILogger logger)
    {
        var updatedDependencyNames = updateOperations.Select(o => o.DependencyName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (updatedDependencyNames.Count == 0)
        {
            return;
        }

        foreach (var project in discoveryResult.Projects)
        {
            var hasLockFile = project.AdditionalFiles.Any(f => Path.GetFileName(f).Equals(ProjectHelper.PackagesLockJsonFileName, StringComparison.OrdinalIgnoreCase));
            var hasUpdatedDependency = project.Dependencies.Any(d => updatedDependencyNames.Contains(d.Name));
            if (!hasLockFile || !hasUpdatedDependency)
            {
                continue;
            }

            var projectPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, project.FilePath).FullyNormalizedRootedPath();
            logger.Info($"Updating lock file for project {Path.Join(discoveryResult.Path, project.FilePath).FullyNormalizedRootedPath()}.");
            await UpdateLockFileAsync(repoContentsPath.FullName, projectPath, logger);
        }
    }
}
