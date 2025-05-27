namespace NuGetUpdater.Core.Run.ApiModel;

public record SecurityUpdateIgnored : JobErrorBase
{
    public SecurityUpdateIgnored(string dependencyName)
        : base("all_versions_ignored")
    {
        Details["dependency-name"] = dependencyName;
    }
}
