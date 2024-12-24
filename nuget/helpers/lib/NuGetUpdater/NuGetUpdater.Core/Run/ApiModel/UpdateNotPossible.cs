namespace NuGetUpdater.Core.Run.ApiModel;

public record UpdateNotPossible : JobErrorBase
{
    public UpdateNotPossible(string[] dependencies)
        : base("update_not_possible")
    {
        Details["dependencies"] = dependencies;
    }
}
