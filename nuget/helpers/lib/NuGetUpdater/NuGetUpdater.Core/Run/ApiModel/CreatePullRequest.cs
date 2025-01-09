using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record CreatePullRequest
{
    public required ReportedDependency[] Dependencies { get; init; }
    [JsonPropertyName("updated-dependency-files")]
    public required DependencyFile[] UpdatedDependencyFiles { get; init; }
    [JsonPropertyName("base-commit-sha")]
    public required string BaseCommitSha { get; init; }
    [JsonPropertyName("commit-message")]
    public required string CommitMessage { get; init; }
    [JsonPropertyName("pr-title")]
    public required string PrTitle { get; init; }
    [JsonPropertyName("pr-body")]
    public required string PrBody { get; init; }
}
