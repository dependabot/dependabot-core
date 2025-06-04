namespace NuGetUpdater.Core.Run.ApiModel;

public record PullRequestExistsForSecurityUpdate : JobErrorBase
{
    public PullRequestExistsForSecurityUpdate(Dependency[] dependencies)
        : base("pull_request_exists_for_security_update")
    {
        Details["updated-dependencies"] = dependencies.Select(d => new Dictionary<string, object>()
        {
            ["dependency-name"] = d.Name,
            ["dependency-version"] = d.Version!,
            ["dependency-removed"] = false,
        }).ToArray();
    }
}
