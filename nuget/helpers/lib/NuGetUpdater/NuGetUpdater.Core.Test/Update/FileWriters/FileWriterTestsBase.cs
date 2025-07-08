using System.Collections.Immutable;

using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public abstract class FileWriterTestsBase
{
    public abstract IFileWriter FileWriter { get; }

    protected async Task TestAsync(
        (string path, string contents)[] files,
        ImmutableArray<string> initialProjectDependencyStrings,
        ImmutableArray<string> requiredDependencyStrings,
        (string path, string contents)[] expectedFiles
    )
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(files);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var initialProjectDependencies = initialProjectDependencyStrings.Select(s => new Dependency(s.Split('/')[0], s.Split('/')[1], DependencyType.Unknown)).ToImmutableArray();
        var requiredDependencies = requiredDependencyStrings.Select(s => new Dependency(s.Split('/')[0], s.Split('/')[1], DependencyType.Unknown)).ToImmutableArray();
        var success = await FileWriter.UpdatePackageVersionsAsync(repoContentsPath, [.. files.Select(f => f.path)], initialProjectDependencies, requiredDependencies);
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
        ImmutableArray<string> initialProjectDependencyStrings,
        ImmutableArray<string> requiredDependencyStrings
    )
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(files);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var initialProjectDependencies = initialProjectDependencyStrings.Select(s => new Dependency(s.Split('/')[0], s.Split('/')[1], DependencyType.Unknown)).ToImmutableArray();
        var requiredDependencies = requiredDependencyStrings.Select(s => new Dependency(s.Split('/')[0], s.Split('/')[1], DependencyType.Unknown)).ToImmutableArray();
        var success = await FileWriter.UpdatePackageVersionsAsync(repoContentsPath, [.. files.Select(f => f.path)], initialProjectDependencies, requiredDependencies);
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
