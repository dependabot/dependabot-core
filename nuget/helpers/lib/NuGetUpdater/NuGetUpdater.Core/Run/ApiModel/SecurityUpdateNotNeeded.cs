namespace NuGetUpdater.Core.Run.ApiModel;

public record SecurityUpdateNotNeeded : JobErrorBase
{
    public SecurityUpdateNotNeeded(string dependencyName)
        : base("security_update_not_needed")
    {
        Details["dependency-name"] = dependencyName;
    }
}
