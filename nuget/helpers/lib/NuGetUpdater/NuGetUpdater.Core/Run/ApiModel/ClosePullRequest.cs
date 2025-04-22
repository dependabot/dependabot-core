using System.Collections.Immutable;
using System.Text;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record ClosePullRequest : MessageBase
{
    [JsonPropertyName("dependency-names")]
    public required ImmutableArray<string> DependencyNames { get; init; }

    public string Reason { get; init; } = "up_to_date";

    public override string GetReport()
    {
        var report = new StringBuilder();
        report.AppendLine($"{nameof(ClosePullRequest)}: {Reason}");
        foreach (var dependencyName in DependencyNames)
        {
            report.AppendLine($"  - {dependencyName}");
        }

        return report.ToString().Trim();
    }
}
