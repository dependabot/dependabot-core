namespace NuGetUpdater.Core.Run.ApiModel;

public record UpdateNotPossible : JobErrorBase
{
    public override string Type => "update_not_possible";
}
