using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run;

public class PullRequestTextGenerator
{
    public static string GetPullRequestTitle(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        // simple version looks like
        //   Update Some.Package to 1.2.3
        // if multiple packages are updated to multiple versions, result looks like:
        //   Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0
        var dependencySets = updateOperationsPerformed
            .GroupBy(d => d.DependencyName, StringComparer.OrdinalIgnoreCase)
            .OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
            .Select(g => new
            {
                Name = g.Key,
                Versions = g
                    .Select(d => d.NewVersion)
                    .OrderBy(v => v)
                    .ToArray()
            })
            .ToArray();
        var updatedPartTitles = dependencySets
            .Select(d => $"{d.Name} to {string.Join(", ", d.Versions.Select(v => v.ToString()))}")
            .ToArray();
        var title = $"{job.CommitMessageOptions?.Prefix}Update {string.Join("; ", updatedPartTitles)}";
        return title;
    }

    public static string GetPullRequestCommitMessage(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        return GetPullRequestTitle(job, updateOperationsPerformed, dependencyGroupName);
    }

    public static string GetPullRequestBody(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        var report = UpdateOperationBase.GenerateUpdateOperationReport(updateOperationsPerformed);
        return report;
    }
}
