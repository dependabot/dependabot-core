namespace NuGetUpdater.Core.Run.ApiModel;

public record UnknownError : JobErrorBase
{
    public UnknownError(string details)
        : base("unknown_error")
    {
        Details = details;
    }
}
