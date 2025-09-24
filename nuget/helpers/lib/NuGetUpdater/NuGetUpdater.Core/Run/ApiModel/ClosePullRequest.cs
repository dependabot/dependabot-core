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
            report.AppendLine($"- {dependencyName}");
        }

        return report.ToString().Trim();
    }

    public static ClosePullRequest WithDependenciesChanged(Job job) => CloseWithReason(job, "dependencies_changed");
    public static ClosePullRequest WithDependenciesRemoved(Job job) => CloseWithReason(job, "dependencies_removed");
    public static ClosePullRequest WithDependencyRemoved(Job job) => CloseWithReason(job, "dependency_removed");
    public static ClosePullRequest WithUpdateNoLongerPossible(Job job) => CloseWithReason(job, "update_no_longer_possible");
    public static ClosePullRequest WithUpToDate(Job job) => CloseWithReason(job, "up_to_date");

    private static ClosePullRequest CloseWithReason(Job job, string reason)
    {
        return new ClosePullRequest()
        {
            DependencyNames = [.. job.Dependencies.Distinct().OrderBy(n => n, StringComparer.OrdinalIgnoreCase)],
            Reason = reason,
        };
    }
}
