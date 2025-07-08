using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public abstract class FileWriterTestsBase
{
    public abstract IFileWriter FileWriter { get; }

    protected async Task TestAsync(
        (string path, string contents)[] files,
        ProjectDiscoveryResult projectDiscovery,
        ImmutableArray<Dependency> requiredDependencies,
        (string path, string contents)[] expectedFiles
    )
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(files);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var success = await FileWriter.UpdatePackageVersionsAsync(repoContentsPath, projectDiscovery, requiredDependencies);
        Assert.True(success);

        var expectedFileNames = expectedFiles.Select(f => f.path).ToHashSet();
        var actualFiles = (await tempDir.ReadFileContentsAsync(expectedFileNames)).ToDictionary(f => f.Path, f => f.Contents);
        foreach (var (expectedPath, expectedContents) in expectedFiles)
        {
            Assert.True(actualFiles.TryGetValue(expectedPath, out var actualContents), $"Expected file {expectedPath} not found.");
            Assert.Equal(expectedContents.Replace("\r", ""), actualContents.Replace("\r", ""));
        }
    }

    protected async Task TestNoChangeAsync(
        (string path, string contents)[] files,
        ProjectDiscoveryResult projectDiscovery,
        ImmutableArray<Dependency> requiredDependencies
    )
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(files);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var success = await FileWriter.UpdatePackageVersionsAsync(repoContentsPath, projectDiscovery, requiredDependencies);
        Assert.False(success);

        var expectedFileNames = files.Select(f => f.path).ToHashSet();
        var actualFiles = (await tempDir.ReadFileContentsAsync(expectedFileNames)).ToDictionary(f => f.Path, f => f.Contents);
        foreach (var (expectedPath, expectedContents) in files)
        {
            Assert.True(actualFiles.TryGetValue(expectedPath, out var actualContents), $"Expected file {expectedPath} not found.");
            Assert.Equal(expectedContents.Replace("\r", ""), actualContents.Replace("\r", ""));
        }
    }
}
