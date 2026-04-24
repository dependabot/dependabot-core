using System.Text;
using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

internal static class EntryPointTestHelper
{
    internal static async Task RunAsync(
        string commandName,
        TestFile[] files,
        Job job,
        string[] expectedUrls,
        MockNuGetPackage[]? packages = null,
        string? repoContentsPath = null,
        int expectedExitCode = 0)
    {
        using var tempDirectory = new TemporaryDirectory();

        // write test files
        foreach (var testFile in files)
        {
            var fullPath = Path.Join(tempDirectory.DirectoryPath, testFile.Path);
            var directory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(directory);
            await File.WriteAllTextAsync(fullPath, testFile.Content);
        }

        // write job file
        var jobPath = Path.Combine(tempDirectory.DirectoryPath, "job.json");
        await File.WriteAllTextAsync(jobPath, JsonSerializer.Serialize(new { Job = job }, RunWorker.SerializerOptions));

        // save packages
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDirectory.DirectoryPath);

        var actualUrls = new List<string>();
        using var http = TestHttpServer.CreateTestStringServer((method, url) =>
        {
            actualUrls.Add($"{method} {new Uri(url).PathAndQuery}");
            return (200, "ok");
        });
        var args = new List<string>()
        {
            commandName,
            "--job-path",
            jobPath,
            "--repo-contents-path",
            repoContentsPath ?? tempDirectory.DirectoryPath,
            "--api-url",
            http.BaseUrl,
            "--job-id",
            "TEST-ID",
            "--base-commit-sha",
            "BASE-COMMIT-SHA"
        };

        var output = new StringBuilder();
        // redirect stdout
        var originalOut = Console.Out;
        Console.SetOut(new StringWriter(output));
        int result = -1;
        try
        {
            result = await Program.Main(args.ToArray());
        }
        catch
        {
            // restore stdout
            Console.SetOut(originalOut);
            throw;
        }

        Assert.True(result == expectedExitCode, $"Expected exit code {expectedExitCode} but got {result}.\nSTDOUT:\n" + output.ToString());
        Assert.Equal(expectedUrls, actualUrls);
    }
}
