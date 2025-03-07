using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public class PullRequestTextGenerator
{
    public static string GetPullRequestTitle(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        return "TODO: title";
    }

    public static string GetPullRequestBody(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        return "TODO: body";
    }

    public static string GetPullRequestCommitMessage(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName = null)
    {
        return "TODO: message";
    }
}
