using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public class RequirementTests
{
    // Supported OPs (=, !=, >, <, >=, <=, ~>)
    [Theory]
    [InlineData("1.0.0", "1.0.0", true)]
    [InlineData("1.0.0-alpha", "1.0.0", false)]
    [InlineData("1.0.0", "= 1.0.0", true)]
    [InlineData("1.0.0-alpha", "= 1.0.0", false)]
    [InlineData("1.0.0", "!= 1.0.1", true)]
    [InlineData("1.0.0", "!= 1.0.0", false)]
    [InlineData("1.0.1", "> 1.0.0", true)]
    [InlineData("1.0.0-alpha", "> 1.0.0", false)]
    [InlineData("1.0.0", "< 1.0.1", true)]
    [InlineData("1.0.0", "< 1.0.0-alpha", false)]
    [InlineData("1.0.0", ">= 1.0.0", true)]
    [InlineData("1.0.1", ">= 1.0.0", true)]
    [InlineData("1.0.0-alpha", ">= 1.0.0", false)]
    [InlineData("1.0.0", "<= 1.0.0", true)]
    [InlineData("1.0.0-alpha", "<= 1.0.0", true)]
    [InlineData("1.0.1", "<= 1.0.0", false)]
    [InlineData("1.0.1", "~> 1.0.0", true)]
    [InlineData("1.1.0", "~> 1.0.0", false)]
    [InlineData("1.1", "~> 1.0", true)]
    [InlineData("2.0", "~> 1.0", false)]
    [InlineData("1", "~> 1", true)]
    [InlineData("2", "~> 1", false)]
    public void IsSatisfiedBy(string versionString, string requirementString, bool expected)
    {
        var version = NuGetVersion.Parse(versionString);
        var requirement = Requirement.Parse(requirementString);

        var actual = requirement.IsSatisfiedBy(version);

        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData("> = 1.0.0")] // Invalid format
    [InlineData("<>= 1.0.0")] // Invalid Operator
    [InlineData(">")] // Missing version
    public void Parse_ThrowsForInvalid(string requirementString)
    {
        Assert.Throws<ArgumentException>(() => Requirement.Parse(requirementString));
    }

    [Theory]
    [InlineData("1.0.0-alpha", "1.1.0.0")]
    [InlineData("1.0.0.0", "1.0.1.0")]
    [InlineData("1.0.0", "1.1.0.0")]
    [InlineData("1.0", "2.0.0.0")]
    [InlineData("1", "2.0.0.0")]
    public void Bump(string versionString, string expectedString)
    {
        var version = NuGetVersion.Parse(versionString);
        var expected = Version.Parse(expectedString);

        var actual = Requirement.Bump(version);

        Assert.Equal(expected, actual);
    }
}
