using System.Text.Json.Serialization;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public sealed record RunResult
{
    [JsonPropertyName("base64_dependency_files")]
    public required DependencyFile[] Base64DependencyFiles { get; init; }
    [JsonPropertyName("base_commit_sha")]
    public required string BaseCommitSha { get; init; }
}
