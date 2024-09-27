namespace NuGetUpdater.Core.Run.ApiModel;

public record UnknownError : JobErrorBase
{
    public override string Type => "unknown_error";
}
