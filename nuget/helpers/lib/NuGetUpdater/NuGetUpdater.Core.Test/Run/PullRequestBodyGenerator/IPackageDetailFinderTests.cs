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
    [InlineData("NUnit version 4.6.1", "v4.6.1", "4.6.1")]
    [InlineData("4.0.262.0", "4.0.262.0", "4.0.262.0")]
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

    [Theory]
    [InlineData("some.package", "some.package v1.0.0", "other.package v2.0.0", "1.0.0")]
    [InlineData("some.package", "other.package v2.0.0", "some.package-v1.0.0", "1.0.0")]
    [InlineData("some.package", "packages/some.package/1.0.0", "other.package v2.0.0", "1.0.0")]
    [InlineData("some.package", "other.package v2.0.0", "v1.0.0", "2.0.0")]
    [InlineData("Azure.AI.VoiceLive", "Azure.AI.VoiceLive_1.1.0", "Azure.AI.VoiceLive_1.1.0", "1.1.0")]
    [InlineData("Microsoft.Azure.Functions.Worker.Extensions.CosmosDB", "Microsoft.Azure.Functions.Worker.Extensions.CosmosDB 4.16.1", "cosmosdb-extension-4.16.1", "4.16.1")]
    [InlineData("Microsoft.NET.Sdk.Functions", "Microsoft.Net.Sdk.Functions 4.1.0", "4.1.0", "4.1.0")]
    [InlineData("System.CommandLine", "System.CommandLine v2.0.2", "v2.0.2", "2.0.2")]
    [InlineData("AWSSDK.S3", "4.0.262.0", "4.0.262.0", "4.0.262.0")]
    public void GetVersionFromNames_WithDependencyName(string dependencyName, string releaseName, string tagName, string expectedVersion)
    {
        var actualVersion = IPackageDetailFinder.GetVersionFromNames(releaseName, tagName, dependencyName);

        Assert.NotNull(actualVersion);
        Assert.Equal(expectedVersion, actualVersion.ToString());
    }

    [Theory]
    [InlineData("some.package", "other.package v1.0.0", "v1.0.0", true)]
    [InlineData("some.package", "some.package v1.0.0", "v1.0.0", false)]
    [InlineData("some.package", "Azure.AI.VoiceLive_1.1.0", "v1.1.0", true)]
    [InlineData("some.package", "System.CommandLine v2.0.2", "v2.0.2", true)]
    [InlineData("some.package", "BenchmarkDotNet v0.15.8", "v0.15.8", false)]
    [InlineData("some.package", "release 1.0.0", "v1.0.0", false)]
    public void HasPackageScopedVersionForOtherDependency(string dependencyName, string releaseName, string tagName, bool expectedResult)
    {
        var actualResult = IPackageDetailFinder.HasPackageScopedVersionForOtherDependency(releaseName, tagName, dependencyName);

        Assert.Equal(expectedResult, actualResult);
    }
}
