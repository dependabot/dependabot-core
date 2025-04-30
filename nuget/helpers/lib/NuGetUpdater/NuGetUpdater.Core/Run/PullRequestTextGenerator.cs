using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run;

public class PullRequestTextGenerator
{
    private const int MaxTitleLength = 70;

    public static string GetPullRequestTitle(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        // simple version looks like
        //   Update Some.Package to 1.2.3
        // if multiple packages are updated to multiple versions, result looks like:
        //   Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0
        var dependencySets = GetDependencySets(updateOperationsPerformed);
        var updatedPartTitles = dependencySets
            .Select(d => $"{d.Name} to {string.Join(", ", d.Versions.Select(v => v.ToString()))}")
            .ToArray();
        var title = $"{job.CommitMessageOptions?.Prefix}Update {string.Join("; ", updatedPartTitles)}";

        // don't let the title get too long
        if (title.Length > MaxTitleLength && updatedPartTitles.Length >= 3)
        {
            title = $"{job.CommitMessageOptions?.Prefix}Update {dependencySets[0].Name} and {dependencySets.Length - 1} other dependencies";
        }

        return title;
    }

    public static string GetPullRequestCommitMessage(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        // updating a single dependency looks like
        //   Update Some.Package to 1.2.3
        // if multiple packages are updated, result looks like:
        //   Update:
        //   - Package.A to 1.0.0
        //   - Package.B to 2.0.0
        var dependencySets = GetDependencySets(updateOperationsPerformed);
        if (dependencySets.Length == 1)
        {
            var depName = dependencySets[0].Name;
            var depVersions = dependencySets[0].Versions.Select(v => v.ToString());
            return $"Update {dependencySets[0].Name} to {string.Join(", ", depVersions)}";
        }

        var updatedParts = dependencySets
            .Select(d => $"- {d.Name} to {string.Join(", ", d.Versions.Select(v => v.ToString()))}")
            .ToArray();
        var message = string.Join("\n", ["Update:", .. updatedParts]);
        return message;
    }

    private static (string Name, NuGetVersion[] Versions)[] GetDependencySets(ImmutableArray<UpdateOperationBase> updateOperationsPerformed)
    {
        var dependencySets = updateOperationsPerformed
            .GroupBy(d => d.DependencyName, StringComparer.OrdinalIgnoreCase)
            .OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                var name = g.Key;
                var versions = g
                    .Select(d => d.NewVersion)
                    .OrderBy(v => v)
                    .ToArray();
                return (name, versions);
            })
            .ToArray();
        return dependencySets;
    }

    public static string GetPullRequestBody(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        var report = UpdateOperationBase.GenerateUpdateOperationReport(updateOperationsPerformed);
        return report;
    }
}
