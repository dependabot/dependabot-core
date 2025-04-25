using System.Collections.Immutable;
using System.Text;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record UpdatePullRequest : MessageBase
{
    [JsonPropertyName("base-commit-sha")]
    public required string BaseCommitSha { get; init; }

    [JsonPropertyName("dependency-names")]
    public required ImmutableArray<string> DependencyNames { get; init; }

    [JsonPropertyName("updated-dependency-files")]
    public required DependencyFile[] UpdatedDependencyFiles { get; init; }

    [JsonPropertyName("pr-title")]
    public required string PrTitle { get; init; }

    [JsonPropertyName("pr-body")]
    public required string PrBody { get; init; }

    [JsonPropertyName("commit-message")]
    public required string CommitMessage { get; init; }

    [JsonPropertyName("dependency-group")]
    public required string? DependencyGroup { get; init; }

    public override string GetReport()
    {
        var dependencyNames = DependencyNames
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var report = new StringBuilder();
        report.AppendLine(nameof(UpdatePullRequest));
        foreach (var d in dependencyNames)
        {
            report.AppendLine($"  - {d}");
        }

        return report.ToString().Trim();
    }
}
