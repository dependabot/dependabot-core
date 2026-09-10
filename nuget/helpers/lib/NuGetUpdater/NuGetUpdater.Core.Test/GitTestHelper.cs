using Xunit;

namespace NuGetUpdater.Core.Test;

public static class GitTestHelper
{
    public static async Task InitializeRepositoryAsync(string workingDirectory, IEnumerable<string> trackedPaths)
    {
        await RunAsync(workingDirectory, "init");

        var paths = trackedPaths.ToArray();
        if (paths.Length > 0)
        {
            await RunAsync(workingDirectory, ["add", "--", .. paths]);
        }
    }

    private static async Task RunAsync(string workingDirectory, params string[] arguments)
    {
        var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("git", arguments, workingDirectory);
        Assert.True(exitCode == 0, $"git {string.Join(' ', arguments)} failed.\nstdout:\n{stdout}\nstderr:\n{stderr}");
    }
}
