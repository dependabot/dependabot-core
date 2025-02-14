using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record ClosePullRequest
{
    [JsonPropertyName("dependency-names")]
    public required ImmutableArray<string> DependencyNames { get; init; }

    public string Reason { get; init; } = "up_to_date";
}
