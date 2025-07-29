namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        var (exitCode, stdout, stderr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", "--force-evaluate", "-p:EnableWindowsTargeting=true", projectPath], projectDirectory);
        if (exitCode != 0)
        {
            logger.Error($"      Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
        }
    }
}
