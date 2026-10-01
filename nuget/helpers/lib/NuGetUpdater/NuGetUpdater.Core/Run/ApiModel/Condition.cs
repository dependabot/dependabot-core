using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record Condition
{
    private static readonly NuGetVersion MinimumVersion = NuGetVersion.Parse("0");

    [JsonPropertyName("dependency-name")]
    public required string DependencyName { get; init; }
    [JsonPropertyName("source")]
    public string? Source { get; init; } = null;
    [JsonPropertyName("update-types")]
    public ConditionUpdateType[]? UpdateTypes { get; init; } = null;
    [JsonPropertyName("updated-at")]
    public DateTime? UpdatedAt { get; init; } = null;
    [JsonPropertyName("version-requirement")]
    public Requirement? VersionRequirement { get; init; } = null;

    internal bool IsUnconditionalIgnore()
    {
        if ((UpdateTypes ?? []).Length > 0)
        {
            return false;
        }

        // Name-only ignore conditions are serialized by the service with a >= 0 requirement.
        return VersionRequirement is null ||
            VersionRequirement is IndividualRequirement { Operator: ">=", Version: var version } &&
            version == MinimumVersion;
    }
}

public enum ConditionUpdateType
{
    [JsonStringEnumMemberName("version-update:semver-major")]
    SemVerMajor,

    [JsonStringEnumMemberName("version-update:semver-minor")]
    SemVerMinor,

    [JsonStringEnumMemberName("version-update:semver-patch")]
    SemVerPatch,
}
