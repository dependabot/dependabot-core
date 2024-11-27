using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class PathHelperTests
{
    [Theory]
    [InlineData("a/b/c", "a/b/c")]
    [InlineData("a/b/../c", "a/c")]
    [InlineData("a/..//c", "c")]
    [InlineData("/a/b/c", "/a/b/c")]
    [InlineData("/a/b/../c", "/a/c")]
    [InlineData("/a/..//c", "/c")]
    [InlineData("a/b/./c", "a/b/c")]
    [InlineData("a/../../b", "b")]
    [InlineData("../../../a/b", "a/b")]
    public void VerifyNormalizeUnixPathParts(string input, string expected)
    {
        var actual = input.NormalizeUnixPathParts();
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void VerifyResolveCaseInsensitivePath()
    {
        using var temp = new TemporaryDirectory();
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "a"));
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "packages.config"), "");

        var repoRootPath = Path.Combine(temp.DirectoryPath, "src");

        var resolvedPath = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Combine(repoRootPath, "A", "PACKAGES.CONFIG"), repoRootPath);

        var expected = Path.Combine(temp.DirectoryPath, "src", "a", "packages.config").NormalizePathToUnix();
        Assert.Equal(expected, resolvedPath!.First());
    }

    [LinuxOnlyFact]
    public void VerifyMultipleMatchingPathsReturnsAllPaths()
    {
        using var temp = new TemporaryDirectory();
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "a"));
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "A"));

        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "packages.config"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "A", "packages.config"), "");

        var repoRootPath = Path.Combine(temp.DirectoryPath, "src");

        var resolvedPaths = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Combine(repoRootPath, "A", "PACKAGES.CONFIG"), repoRootPath);

        var expected = new[]
        {
            Path.Combine(temp.DirectoryPath, "src", "a", "packages.config").NormalizePathToUnix(),
            Path.Combine(temp.DirectoryPath, "src", "A", "packages.config").NormalizePathToUnix(),
        };

        Assert.Equal(expected, resolvedPaths!);
    }

    [LinuxOnlyFact]
    public async void FilesWithDifferentlyCasedDirectoriesCanBeResolved()
    {
        // arrange
        using var temp = new TemporaryDirectory();
        var testFile1 = "src/project1/project1.csproj";
        var testFile2 = "SRC/project2/project2.csproj";
        var testFiles = new[] { testFile1, testFile2 };
        foreach (var testFile in testFiles)
        {
            var fullPath = Path.Join(temp.DirectoryPath, testFile); Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            await File.WriteAllTextAsync(fullPath, "");
        }

        // act        
        var actualFile1 = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Join(temp.DirectoryPath, testFile1), temp.DirectoryPath);
        var actualFile2 = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Join(temp.DirectoryPath, testFile2), temp.DirectoryPath);

        // assert        
        Assert.EndsWith(testFile1, actualFile1![0]); Assert.EndsWith(testFile2, actualFile2![0]);
    }
}
