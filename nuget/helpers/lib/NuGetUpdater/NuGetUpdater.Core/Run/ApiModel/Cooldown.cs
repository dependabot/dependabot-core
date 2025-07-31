using System.Collections.Immutable;
using System.IO.Enumeration;
using System.Text.Json.Serialization;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.ApiModel;

public record Cooldown
{
    [JsonPropertyName("default-days")]
    public int DefaultDays { get; init; } = 0;

    [JsonPropertyName("semver-major-days")]
    public int SemVerMajorDays { get; init; } = 0;

    [JsonPropertyName("semver-minor-days")]
    public int SemVerMinorDays { get; init; } = 0;

    [JsonPropertyName("semver-patch-days")]
    public int SemVerPatchDays { get; init; } = 0;

    [JsonPropertyName("include")]
    public ImmutableArray<string>? Include { get; init; } = null;

    [JsonPropertyName("exclude")]
    public ImmutableArray<string>? Exclude { get; init; } = null;

    public bool AppliesToPackage(string packageName)
    {
        var isExcluded = Exclude?.Any(exclude => FileSystemName.MatchesSimpleExpression(exclude, packageName)) ?? false;
        if (isExcluded)
        {
            return false;
        }

        var isIncluded = Include is null ||
            Include.Value.Length == 0 ||
            Include.Value.Any(include => FileSystemName.MatchesSimpleExpression(include, packageName));
        return isIncluded;
    }

    public int GetCooldownDays(NuGetVersion currentPackageVersion, NuGetVersion candidateUpdateVersion)
    {
        var majorDays = SemVerMajorDays > 0 ? SemVerMajorDays : DefaultDays;
        var minorDays = SemVerMinorDays > 0 ? SemVerMinorDays : DefaultDays;
        var patchDays = SemVerPatchDays > 0 ? SemVerPatchDays : DefaultDays;

        var isMajorBump = candidateUpdateVersion.Major > currentPackageVersion.Major;
        var isMinorBump = candidateUpdateVersion.Major == currentPackageVersion.Major && candidateUpdateVersion.Minor > currentPackageVersion.Minor;
        var isPatchBump = candidateUpdateVersion.Major == currentPackageVersion.Major && candidateUpdateVersion.Minor == currentPackageVersion.Minor && candidateUpdateVersion.Patch > currentPackageVersion.Patch;

        if (isMajorBump)
        {
            return majorDays;
        }
        else if (isMinorBump)
        {
            return minorDays;
        }
        else if (isPatchBump)
        {
            return patchDays;
        }

        // possible if it's a change in pre-release version
        return DefaultDays;
    }

    public bool IsVersionUpdateAllowed(DateTimeOffset currentTime, DateTimeOffset? packagePublishTime, NuGetVersion currentPackageVersion, NuGetVersion candidateUpdateVersion)
    {
        if (packagePublishTime is null)
        {
            // default to allow it
            return true;
        }

        var daysSincePublish = (currentTime - packagePublishTime.Value).TotalDays;
        var requiredCooldownDays = GetCooldownDays(currentPackageVersion, candidateUpdateVersion);
        var isUpdateAllowed = daysSincePublish >= requiredCooldownDays;
        return isUpdateAllowed;
    }
}
