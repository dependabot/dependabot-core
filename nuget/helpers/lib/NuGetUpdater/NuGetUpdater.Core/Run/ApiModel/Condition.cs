using System.Text.Json.Serialization;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record Condition
{
    [JsonPropertyName("dependency-name")]
    public required string DependencyName { get; init; }
    [JsonPropertyName("source")]
    public string? Source { get; init; } = null;
    [JsonPropertyName("update-types")]
    public string[] UpdateTypes { get; init; } = [];
    [JsonPropertyName("updated-at")]
    public DateTime? UpdatedAt { get; init; } = null;
    [JsonPropertyName("version-requirement")]
    public Requirement? VersionRequirement { get; init; } = null;
}
