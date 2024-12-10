namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        await MSBuildHelper.HandleGlobalJsonAsync(projectDirectory, repoRootPath, experimentsManager, async () =>
        {
            var (exitCode, stdout, stderr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", "--force-evaluate", projectPath], projectDirectory, experimentsManager);
            if (exitCode != 0)
            {
                logger.Error($"      Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
            }
            return (exitCode, stdout, stderr);
        }, logger, retainMSBuildSdks: true);
    }
}
