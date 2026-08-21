using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    /// <summary>
    /// Regenerates the `packages.lock.json` file of every discovered project that has one.  This can't be left to the
    /// plain restore that discovery performs: a project with `RestoreLockedMode` set will refuse to rewrite an
    /// out-of-date lock file and report NU1004 instead, and with Central Package Management the version change lands
    /// in a `Directory.Packages.props` that the lock-file-owning project merely imports, so the pinned transitive
    /// versions are never re-resolved.  `dotnet restore --force-evaluate` is the only command that rewrites the lock
    /// file in either case.
    /// </summary>
    public static async Task UpdateLockFilesAsync(
        DirectoryInfo repoContentsPath,
        WorkspaceDiscoveryResult discoveryResult,
        ILogger logger)
    {
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
            await UpdateLockFileAsync(projectPath, requiresWindowsTargeting, logger);
        }
    }

    private static async Task UpdateLockFileAsync(
        string projectPath,
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
