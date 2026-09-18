using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    /// <summary>
    /// Regenerates the `packages.lock.json` file of every discovered project that has one.  The restore discovery
    /// performs after a write isn't enough on its own: it is scoped to the project that was written, so under Central
    /// Package Management a sibling project that merely imports the updated `Directory.Packages.props` is never
    /// re-resolved and keeps a lock file that no longer agrees with it.  `--force-evaluate` also rewrites the lock
    /// file whatever the consumer's `RestoreLockedMode` says, which a plain restore refuses to do.
    /// </summary>
    public static async Task UpdateLockFilesAsync(
        DirectoryInfo repoContentsPath,
        WorkspaceDiscoveryResult discoveryResult,
        ILogger logger)
    {
        var solutionDirectory = discoveryResult.SolutionDirectory is null
            ? null
            : Path.Join(repoContentsPath.FullName, discoveryResult.SolutionDirectory).FullyNormalizedRootedPath();

        foreach (var project in discoveryResult.Projects)
        {
            // `AdditionalFiles` entries are relative to the project's own directory
            var hasLockFile = project.AdditionalFiles.Any(f => Path.GetFileName(f).Equals(ProjectHelper.PackagesLockJsonFileName, StringComparison.OrdinalIgnoreCase));
            if (!hasLockFile)
            {
                continue;
            }

            var projectPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, project.FilePath).FullyNormalizedRootedPath();
            if (!File.Exists(projectPath))
            {
                continue;
            }

            var requiresWindowsTargeting = project.TargetFrameworks.Any(tfm => tfm.Contains("-windows", StringComparison.OrdinalIgnoreCase));
            logger.Info($"Regenerating lock file for project [{project.FilePath}]");
            await UpdateLockFileAsync(projectPath, solutionDirectory, requiresWindowsTargeting, logger);
        }
    }

    private static async Task UpdateLockFileAsync(
        string projectPath,
        string? solutionDirectory,
        bool requiresWindowsTargeting,
        ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        var args = new List<string>()
        {
            "restore",
            "--force-evaluate",
            // if using CPM and a project also sets TreatWarningsAsErrors to true, this can cause the restore to fail; explicitly don't allow that
            "-p:TreatWarningsAsErrors=false",
            "-p:MSBuildTreatWarningsAsErrors=false",
        };
        if (solutionDirectory is not null)
        {
            var normalizedSolutionDirectory = $"{solutionDirectory.TrimEnd('/', Path.DirectorySeparatorChar)}/";
            args.Add($"-p:SolutionDir={normalizedSolutionDirectory}");
        }

        if (requiresWindowsTargeting)
        {
            args.Add("-p:EnableWindowsTargeting=true");
        }

        args.Add(projectPath);
        var (exitCode, stdout, stderr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(args, projectDirectory);
        if (exitCode != 0)
        {
            // a failed lock file regeneration shouldn't fail the whole update; report it and keep going
            logger.Error($"  Lock file update failed for [{projectPath}].\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
        }
    }
}
