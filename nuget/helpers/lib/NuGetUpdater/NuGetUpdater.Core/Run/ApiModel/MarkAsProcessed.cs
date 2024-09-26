using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record MarkAsProcessed
{
    [JsonPropertyName("base-commit-sha")]
    public required string BaseCommitSha { get; init; }
}
