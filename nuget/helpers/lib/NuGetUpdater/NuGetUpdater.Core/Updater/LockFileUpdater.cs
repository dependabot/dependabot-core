namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        Logger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        var lockPath = Path.Combine(projectDirectory, "packages.lock.json");
        logger.Log($"      Updating lock file");
        if (!File.Exists(lockPath))
        {
            logger.Log($"    File [{Path.GetRelativePath(repoRootPath, lockPath)}] does not exist.");
            return;
        }

        await MSBuildHelper.SidelineGlobalJsonAsync(projectDirectory, repoRootPath, async () =>
        {
            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", $"restore --force-evaluate {projectPath}", workingDirectory: projectDirectory);
            if (exitCode != 0)
            {
                logger.Log($"    Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
            }
        }, retainMSBuildSdks: true);
    }
}
