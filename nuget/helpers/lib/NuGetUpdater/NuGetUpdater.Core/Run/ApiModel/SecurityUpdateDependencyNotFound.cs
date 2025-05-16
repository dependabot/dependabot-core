namespace NuGetUpdater.Core.Run.ApiModel;

public record SecurityUpdateDependencyNotFound : JobErrorBase
{
    public SecurityUpdateDependencyNotFound()
        : base("security_update_dependency_not_found")
    {
    }
}
