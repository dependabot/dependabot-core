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
    [InlineData("1.0.0", "!=1.0.1", true)]
    [InlineData("1.0.0", "!= 1.0.0", false)]
    [InlineData("1.0.1", "> 1.0.0", true)]
    [InlineData("1.0.0-alpha", "> 1.0.0", false)]
    [InlineData("1.0.0", "< 1.0.1", true)]
    [InlineData("1.0.0", "<1.0.0-alpha", false)]
    [InlineData("1.0.0", ">= 1.0.0", true)]
    [InlineData("1.0.1", ">= 1.0.0", true)]
    [InlineData("1.0.0-alpha", ">= 1.0.0", false)]
    [InlineData("1.0.0", "<= 1.0.0", true)]
    [InlineData("1.0.0-alpha", "<= 1.0.0", true)]
    [InlineData("1.0.1", "<= 1.0.0", false)]
    [InlineData("1.0.1", "~>1.0.0", true)]
    [InlineData("1.1.0", "~> 1.0.0", false)]
    [InlineData("1.1", "~> 1.0", true)]
    [InlineData("2.0", "~> 1.0", false)]
    [InlineData("1", "~> 1", true)]
    [InlineData("2", "~> 1", false)]
    [InlineData("5.3.8", "< 6, > 5.2.4", true)]
    [InlineData("1.0-preview", ">= 1.x", false)] // wildcards
    [InlineData("1.1-preview", ">= 1.x", true)]
    public void IsSatisfiedBy(string versionString, string requirementString, bool expected)
    {
        var version = NuGetVersion.Parse(versionString);
        var requirement = Requirement.Parse(requirementString);

        var actual = requirement.IsSatisfiedBy(version);

        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData("> 1.*", "> 1.0")] // standard wildcard, single digit
    [InlineData("> 1.2.*", "> 1.2.0")] // standard wildcard, multiple digit
    [InlineData("> 1.a", "> 1.0")] // alternate wildcard, single digit
    [InlineData("> 1.2.a", "> 1.2.0")] // alternate wildcard, multiple digit
    public void Parse_ConvertsWildcardInVersion(string givenRequirementString, string expectedRequirementString)
    {
        var parsedRequirement = Requirement.Parse(givenRequirementString);
        var actualRequirementString = parsedRequirement.ToString();
        Assert.Equal(expectedRequirementString, actualRequirementString);
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
