using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.ApiModel;

public class CooldownTests
{
    [Theory]
    [InlineData("2025-07-04T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "2.0.0", true)] // 3 days later - major allowed
    [InlineData("2025-07-04T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.1.0", true)] // 3 days later - minor allowed
    [InlineData("2025-07-04T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.0.1", true)] // 3 days later - patch allowed
    [InlineData("2025-07-03T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "2.0.0", false)] // 2 days later - major not allowed
    [InlineData("2025-07-03T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.1.0", true)] // 2 days later - minor allowed
    [InlineData("2025-07-03T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.0.1", true)] // 2 days later - patch allowed
    [InlineData("2025-07-02T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "2.0.0", false)] // 1 day later - major not allowed
    [InlineData("2025-07-02T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.1.0", false)] // 1 day later - minor not allowed
    [InlineData("2025-07-02T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.0.1", true)] // 1 day later - patch allowed
    [InlineData("2025-07-01T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "2.0.0", false)] // same day - major not allowed
    [InlineData("2025-07-01T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.1.0", false)] // same day - minor not allowed
    [InlineData("2025-07-01T00:00:00Z", "2025-07-01T00:00:00Z", "1.0.0", "1.0.1", false)] // same day - patch not allowed
    [InlineData("2025-07-01T00:00:00Z", null, "1.0.0", "2.0.0", true)] // no publish date - major allowed
    [InlineData("2025-07-01T00:00:00Z", null, "1.0.0", "1.1.0", true)] // no publish date - minor allowed
    [InlineData("2025-07-01T00:00:00Z", null, "1.0.0", "1.0.1", true)] // no publish date - patch allowed
    public void Cooldown(string currentTimeString, string? packagePublishTimeString, string currentVersionString, string candidateVersionString, bool expectedIsUpdateAllowed)
    {
        // all scenarios use the same configuration
        var cooldown = new Cooldown()
        {
            DefaultDays = 4,
            SemVerMajorDays = 3,
            SemVerMinorDays = 2,
            SemVerPatchDays = 1,
        };
        var currentTime = DateTimeOffset.Parse(currentTimeString);
        var packagePublishTime = packagePublishTimeString is null ? (DateTimeOffset?)null : DateTimeOffset.Parse(packagePublishTimeString);
        var currentVersion = NuGetVersion.Parse(currentVersionString);
        var candidateVersion = NuGetVersion.Parse(candidateVersionString);
        var actualIsUpdateAllowed = cooldown.IsVersionUpdateAllowed(currentTime, packagePublishTime, currentVersion, candidateVersion);
        Assert.Equal(expectedIsUpdateAllowed, actualIsUpdateAllowed);
    }

    [Theory]
    [InlineData(4, 3, 2, 1, "1.0.0", "2.0.0", 3)] // major update allowed after 3 days
    [InlineData(4, 3, 2, 1, "1.0.0", "1.1.0", 2)] // minor update allowed after 2 days
    [InlineData(4, 3, 2, 1, "1.0.0", "1.0.1", 1)] // patch update allowed after 1 day
    [InlineData(4, 0, 0, 0, "1.0.0", "2.0.0", 4)] // major update allowed after default days
    [InlineData(4, 0, 0, 0, "1.0.0", "1.1.0", 4)] // minor update allowed after default days
    [InlineData(4, 0, 0, 0, "1.0.0", "1.0.1", 4)] // patch update allowed after default day
    [InlineData(4, 3, 2, 1, "1.0.0-beta1", "1.0.0-beta2", 4)] // default update allowed after 4 days
    public void GetCooldownDays(int defaultDays, int semverMajorDays, int semverMinorDays, int semverPatchDays, string currentVersionString, string candidateUpdateVersioString, int expectedDaysDelay)
    {
        var cooldown = new Cooldown()
        {
            DefaultDays = defaultDays,
            SemVerMajorDays = semverMajorDays,
            SemVerMinorDays = semverMinorDays,
            SemVerPatchDays = semverPatchDays,
        };
        var currentVersion = NuGetVersion.Parse(currentVersionString);
        var candidateUpdateVersion = NuGetVersion.Parse(candidateUpdateVersioString);
        var actualDaysDelay = cooldown.GetCooldownDays(currentVersion, candidateUpdateVersion);
        Assert.Equal(expectedDaysDelay, actualDaysDelay);
    }

    [Theory]
    [InlineData(null, null, "Some.Package", true)] // no include, no exclude - always applies
    [InlineData("", null, "Some.Package", true)] // empty include, no exclude - always applies
    [InlineData("*", null, "Some.Package", true)] // wildcard include, no exclude - always applies
    [InlineData(null, "", "Some.Package", true)] // no include, empty exclude - always applies
    [InlineData("", "", "Some.Package", true)] // empty include, empty exclude - always applies
    [InlineData("*", "", "Some.Package", true)] // wildcard include, empty exclude - always applies
    [InlineData(null, "*", "Some.Package", false)] // no include, wildcard exclude - never applies
    [InlineData("", "*", "Some.Package", false)] // empty include, wildcard exclude - never applies
    [InlineData(null, "Some.*", "Some.Package", false)] // no include, exclude pattern match - doesn't apply
    [InlineData("", "Some.*", "Some.Package", false)] // empty include, exclude pattern match - doesn't apply
    [InlineData("*", "Some.*", "Some.Package", false)] // wildcard include, exclude pattern match - doesn't apply
    [InlineData("*", "Some.*", "Other.Package", true)] // wildcard include, exclude doesn't match - applies
    [InlineData("Some.*", null, "Some.Package", true)] // include pattern match, no exclude - applies
    [InlineData("Some.*", "", "Some.Package", true)] // include pattern match, empty exclude - applies
    [InlineData("Some.*", null, "Other.Package", false)] // include pattern doesn't match, no exclude - doesn't apply
    [InlineData("Some.*", "", "Other.Package", false)] // include pattern doesn't match, empty exclude - doesn't apply
    [InlineData("Some.*", "Some.Other.*", "Some.Package", true)] // include pattern match, exclude pattern doesn't match - applies
    [InlineData("Some.*", "Some.Other.*", "Some.Other.Package", false)] // include pattern match, exclude pattern match - doesn't apply
    public void CooldownAppliesToPackage(string? includeString, string? excludeString, string packageName, bool expectedResult)
    {
        var cooldown = new Cooldown()
        {
            Include = includeString?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToImmutableArray(),
            Exclude = excludeString?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToImmutableArray(),
        };
        var actualResult = cooldown.AppliesToPackage(packageName);
        Assert.Equal(expectedResult, actualResult);
    }
}
