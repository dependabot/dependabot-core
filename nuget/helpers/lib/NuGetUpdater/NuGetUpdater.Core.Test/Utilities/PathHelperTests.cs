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

        var resolvedPath = PathHelper.ResolveCaseInsensitivePathInsideRepoRoot(Path.Combine(repoRootPath, "A", "PACKAGES.CONFIG"), repoRootPath);

        var expected = Path.Combine(temp.DirectoryPath, "src", "a", "packages.config").NormalizePathToUnix();
        Assert.Equal(expected, resolvedPath);
    }
}
