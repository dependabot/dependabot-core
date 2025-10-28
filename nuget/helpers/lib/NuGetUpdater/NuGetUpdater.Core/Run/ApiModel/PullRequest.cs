using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public record PullRequest
{
    [JsonPropertyName("pr-number")]
    public int? PrNumber { get; init; } = null;
    [JsonPropertyName("dependencies")]
    public ImmutableArray<PullRequestDependency> Dependencies { get; init; } = [];
}
