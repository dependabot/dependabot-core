namespace NuGetUpdater.Core;

internal static class LockFileUpdater
{
    public static async Task UpdateLockFileAsync(
        string repoRootPath,
        string projectPath,
        ILogger logger)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        await MSBuildHelper.SidelineGlobalJsonAsync(projectDirectory, repoRootPath, async () =>
        {
            var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("dotnet", ["restore", "--force-evaluate", projectPath], workingDirectory: projectDirectory);
            if (exitCode != 0)
            {
                logger.Error($"      Lock file update failed.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
            }
            return (exitCode, stdout, stderr);
        }, logger, retainMSBuildSdks: true);
    }
}
