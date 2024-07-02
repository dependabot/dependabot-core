namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        Logger logger)
    {
        var lockPath = Path.Combine(Path.GetDirectoryName(projectPath), "packages.lock.json");
        logger.Log($"  Running for lock file");
        if (!File.Exists(lockPath))
        {
            logger.Log($"    File [{Path.GetRelativePath(repoRootPath, lockPath)}] does not exist.");
            return;
        }

        var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", $"restore --force-evaluate {projectPath}");
        if (exitCode != 0)
        {
            logger.Log($"    Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
            return;
        }

        logger.Log($"    Saved [{Path.GetRelativePath(repoRootPath, lockPath)}].");
    }
}
