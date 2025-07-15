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
    public void CreateUpdatedVersionRange(string existingRangeString, string existingVersionString, string newVersionString, string expectedNewRangeString)
    {
        var existingRange = VersionRange.Parse(existingRangeString);
        var existingVersion = NuGetVersion.Parse(existingVersionString);
        var newVersion = NuGetVersion.Parse(newVersionString);

        var actualNewRangeString = XmlFileWriter.CreateUpdatedVersionRangeString(existingRange, existingVersion, newVersion);

        Assert.Equal(expectedNewRangeString, actualNewRangeString);
    }
}
