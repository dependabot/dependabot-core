using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record ReportedDependency
{
    public required string Name { get; init; }
    public required string? Version { get; init; }
    public required ReportedRequirement[] Requirements { get; init; }
    [JsonPropertyName("previous-version")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? PreviousVersion { get; init; } = null;
    [JsonPropertyName("previous-requirements")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public ReportedRequirement[]? PreviousRequirements { get; init; } = null;
}
