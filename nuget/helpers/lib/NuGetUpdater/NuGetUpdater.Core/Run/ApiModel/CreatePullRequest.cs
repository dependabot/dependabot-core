using System.Text;
using System.Text.Json.Serialization;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record CreatePullRequest : MessageBase
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

    public override string GetReport()
    {
        var dependencyNames = Dependencies
            .OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(d => NuGetVersion.Parse(d.Version!))
            .Select(d => $"{d.Name}/{d.Version}")
            .ToArray();
        var report = new StringBuilder();
        report.AppendLine(nameof(CreatePullRequest));
        foreach (var d in dependencyNames)
        {
            report.AppendLine($"  - {d}");
        }

        return report.ToString().Trim();
    }
}
