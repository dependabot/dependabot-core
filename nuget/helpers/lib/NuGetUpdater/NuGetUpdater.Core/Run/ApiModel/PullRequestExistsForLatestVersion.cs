namespace NuGetUpdater.Core.Run.ApiModel;

public record PullRequestExistsForLatestVersion : JobErrorBase
{
    public PullRequestExistsForLatestVersion(string dependencyName, string dependencyVersion)
        : base("pull_request_exists_for_latest_version")
    {
        Details["dependency-name"] = dependencyName;
        Details["dependency-version"] = dependencyVersion;
    }
}
