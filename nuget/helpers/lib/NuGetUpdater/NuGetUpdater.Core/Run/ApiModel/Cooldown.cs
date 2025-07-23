using System.Collections.Immutable;
using System.Text.Json.Serialization;

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
}
