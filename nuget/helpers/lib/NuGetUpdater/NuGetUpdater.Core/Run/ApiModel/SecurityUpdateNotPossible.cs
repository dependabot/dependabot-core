namespace NuGetUpdater.Core.Run.ApiModel;

public record SecurityUpdateNotPossible : JobErrorBase
{
    public SecurityUpdateNotPossible(string dependencyName, string latestResolvableVersion, string lowestNonVulnerableVersion, string[] conflictingDependencies)
        : base("security_update_not_possible")
    {
        Details["dependency-name"] = dependencyName;
        Details["latest-resolvable-version"] = latestResolvableVersion;
        Details["lowest-non-vulnerable-version"] = lowestNonVulnerableVersion;
        Details["conflicting-dependencies"] = conflictingDependencies;
    }
}
