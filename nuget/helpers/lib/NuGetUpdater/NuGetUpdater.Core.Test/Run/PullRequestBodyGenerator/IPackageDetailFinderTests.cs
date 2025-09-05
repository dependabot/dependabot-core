using NuGetUpdater.Core.Run.PullRequestBodyGenerator;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.PullRequestBodyGenerator;

public class IPackageDetailFinderTests
{
    [Theory]
    [InlineData("1.0.0", "1.0.0", "1.0.0")]
    [InlineData("one.zero.zero", "1.0.0", "1.0.0")]
    [InlineData("version-one.zero.zero", "v1.0.0", "1.0.0")]
    [InlineData("v-one.zero.zero", "v-one.zero.zero", null)]
    [InlineData("Stable", "version-1.0.0", "1.0.0")]
    [InlineData("some.package/1.0.0", "some.package/1.0.0", "1.0.0")]
    [InlineData("some.package 1.0.0", "some.package 1.0.0", "1.0.0")]
    public void GetVersionFromNames(string releaseName, string tagName, string? expectedVersion)
    {
        var actualVersion = IPackageDetailFinder.GetVersionFromNames(releaseName, tagName);
        if (expectedVersion is null)
        {
            Assert.Null(actualVersion);
        }
        else
        {
            Assert.NotNull(actualVersion);
            Assert.Equal(expectedVersion, actualVersion.ToString());
        }
    }
}
