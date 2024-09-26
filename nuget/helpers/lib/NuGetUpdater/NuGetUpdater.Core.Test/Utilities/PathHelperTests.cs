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
}
