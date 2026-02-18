using NuGet.Versioning;

using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests_CreateUpdatedVersionRangeTests
{
    [Theory]
    [InlineData("[1.0.0]", "1.0.0", "2.0.0", "[2.0.0]")] // single exact version
    [InlineData("[1.0.0, 3.0.0)", "1.0.0", "2.0.0", "[2.0.0, 3.0.0)")] // narrowing of range
    [InlineData("[1.0.0, 2.0.0)", "1.0.0", "2.0.0", "2.0.0")] // narrowing of range to simple version string
    [InlineData("*", "1.0.1", "2.0.0", "*")] // wildcard is retained at major level
    [InlineData("1.*", "1.0.1", "2.0.0", "2.*")] // wildcard is retained at minor level
    [InlineData("1.0.*", "1.0.1", "2.0.0", "2.0.*")] // wildcard is retained at patch level
    [InlineData("1.0.0.*", "1.0.1.0", "2.0.0", "2.0.0.*")] // wildcard is retained at revision level
    [InlineData("1.0.0.*", "1.0.1", "2.0", "2.0.0.*")] // wildcard is retained at revision level with a shorter updated version
    [InlineData("10.*-*", "10.0-beta1", "11.0-beta2", "11.*-*")] // wildcard with prerelease
    [InlineData("10.*-preview*", "10.0-preview1", "11.0-preview4", "11.*-preview*")] // wildcard with specific prerelease
    [InlineData("10.0.0-preview.*", "10.0.0-preview.1", "11.0.0-preview.2", "11.0.0-preview.*")] // wildcard in prerelease
    public void CreateUpdatedVersionRange(string existingRangeString, string existingVersionString, string newVersionString, string expectedNewRangeString)
    {
        var existingRange = VersionRange.Parse(existingRangeString);
        var existingVersion = NuGetVersion.Parse(existingVersionString);
        var newVersion = NuGetVersion.Parse(newVersionString);

        var actualNewRangeString = XmlFileWriter.CreateUpdatedVersionRangeString(existingRange, existingVersion, newVersion);

        Assert.Equal(expectedNewRangeString, actualNewRangeString);
    }
}
