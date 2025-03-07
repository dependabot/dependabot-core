using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public class PullRequestTextGenerator
{
    public static string GetPullRequestTitle(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        // simple version looks like
        //   Update Some.Package to 1.2.3
        // if multiple packages are updated to multiple versions, result looks like:
        //   Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0
        var dependencySets = updatedDependencies
            .GroupBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
            .Select(g => new
            {
                Name = g.Key,
                Versions = g
                    .Where(d => d.Version is not null)
                    .Select(d => d.Version!)
                    .OrderBy(d => NuGetVersion.Parse(d))
                    .ToArray()
            })
            .ToArray();
        var updatedPartTitles = dependencySets
            .Select(d => $"{d.Name} to {string.Join(", ", d.Versions)}")
            .ToArray();
        var title = $"{job.CommitMessageOptions?.Prefix}Update {string.Join("; ", updatedPartTitles)}";
        return title;
    }

    public static string GetPullRequestCommitMessage(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        return GetPullRequestTitle(job, updatedDependencies, updatedFiles, dependencyGroupName);
    }

    public static string GetPullRequestBody(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        return GetPullRequestTitle(job, updatedDependencies, updatedFiles, dependencyGroupName);
    }
}
