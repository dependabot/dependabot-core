namespace NuGetUpdater.Core.Run.ApiModel;

public record SecurityUpdateNotFound : JobErrorBase
{
    public SecurityUpdateNotFound(string dependencyName, string dependencyVersion)
        : base("security_update_not_found")
    {
        Details["dependency-name"] = dependencyName;
        Details["dependency-version"] = dependencyVersion;
    }
}
