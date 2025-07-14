using System.Collections.Immutable;
using System.Text;
using System.Text.RegularExpressions;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using DependencySet = (string Name, (NuGet.Versioning.NuGetVersion? OldVersion, NuGet.Versioning.NuGetVersion NewVersion)[] Versions);

namespace NuGetUpdater.Core.Run;

public class PullRequestTextGenerator
{
    private const int MaxTitleLength = 70;

    public static string GetPullRequestTitle(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        var shortTitle = GetPullRequestShortTitle(job, updateOperationsPerformed, dependencyGroupName);
        var titlePrefix = GetPullRequestTitlePrefix(job);
        var fullTitle = $"{titlePrefix}{shortTitle}";
        return fullTitle;
    }

    private static string GetPullRequestTitlePrefix(Job job)
    {
        if (string.IsNullOrEmpty(job.CommitMessageOptions?.Prefix))
        {
            return string.Empty;
        }

        var prefix = job.CommitMessageOptions?.Prefix ?? string.Empty;
        if (Regex.IsMatch(prefix, @"[a-z0-9\)\]]$", RegexOptions.IgnoreCase))
        {
            prefix += ":";
        }

        if (!prefix.EndsWith(" "))
        {
            prefix += " ";
        }

        return prefix;
    }

    private static string GetPullRequestShortTitle(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        string title;
        var dependencySets = GetDependencySets(updateOperationsPerformed);
        if (dependencyGroupName is not null)
        {
            title = $"Bump the {dependencyGroupName} group with {dependencySets.Length} update{(dependencySets.Length > 1 ? "s" : "")}";
        }
        else
        {
            if (dependencySets.Length == 1)
            {
                title = GetDependencySetBumpText(dependencySets[0], isCommitMessageDetail: false);
            }
            else
            {
                var dependencyNames = dependencySets.Select(d => d.Name).Distinct().OrderBy(n => n).ToArray();
                title = $"Bump {string.Join(", ", dependencyNames.Take(dependencyNames.Length - 1))} and {dependencyNames[^1]}";

                // don't let the title get too long
                if (title.Length > MaxTitleLength && dependencyNames.Length >= 3)
                {
                    title = $"Bump {dependencyNames[0]} and {dependencyNames.Length - 1} others";
                }
            }
        }

        return title;
    }

    public static string GetPullRequestCommitMessage(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        var sb = new StringBuilder();
        sb.AppendLine(GetPullRequestTitle(job, updateOperationsPerformed, dependencyGroupName));
        var dependencySets = GetDependencySets(updateOperationsPerformed);
        if (dependencySets.Length > 1 ||
            dependencyGroupName is not null)
        {
            // multiple updates performed, enumerate them
            sb.AppendLine();
            foreach (var dependencySet in dependencySets)
            {
                sb.AppendLine(GetDependencySetBumpText(dependencySet, isCommitMessageDetail: true));
            }
        }

        return sb.ToString().Replace("\r", "").TrimEnd();
    }

    private static string GetDependencySetBumpText(DependencySet dependencySet, bool isCommitMessageDetail)
    {
        var bumpSuffix = isCommitMessageDetail ? "s" : string.Empty; // "Bumps" for commit message details, "Bump" otherwise
        var fromText = dependencySet.Versions.Length == 1 && dependencySet.Versions[0].OldVersion is not null
            ? $"from {dependencySet.Versions[0].OldVersion} "
            : string.Empty;
        var newVersions = dependencySet.Versions
            .Select(v => v.NewVersion)
            .Distinct()
            .OrderBy(v => v)
            .ToArray();
        return $"Bump{bumpSuffix} {dependencySet.Name} {fromText}to {string.Join(", ", newVersions.Select(v => v.ToString()))}";
    }

    private static DependencySet[] GetDependencySets(ImmutableArray<UpdateOperationBase> updateOperationsPerformed)
    {
        var dependencySets = updateOperationsPerformed
            .GroupBy(d => d.DependencyName, StringComparer.OrdinalIgnoreCase)
            .OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                var name = g.Key;
                var versions = g
                    .OrderBy(d => d.OldVersion)
                    .ThenBy(d => d.NewVersion)
                    .Select(d => (d.OldVersion, d.NewVersion))
                    .ToArray();
                return (name, versions);
            })
            .ToArray();
        return dependencySets;
    }

    public static string GetPullRequestBody(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, string? dependencyGroupName)
    {
        var report = UpdateOperationBase.GenerateUpdateOperationReport(updateOperationsPerformed, includeFileNames: false);
        return report;
    }
}
