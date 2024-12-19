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
            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", ["restore", "--force-evaluate", "-p:EnableWindowsTargeting=true", projectPath], workingDirectory: projectDirectory);
            if (exitCode != 0)
            {
                logger.Error($"      Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
            }
            return (exitCode, stdout, stderr);
        }, logger, retainMSBuildSdks: true);
    }
}
