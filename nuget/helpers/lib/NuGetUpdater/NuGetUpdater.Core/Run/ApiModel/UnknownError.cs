namespace NuGetUpdater.Core.Run.ApiModel;

public record UnknownError : JobErrorBase
{
    public UnknownError(Exception ex, string jobId)
        : base("unknown_error")
    {
        Details["error-class"] = ex.GetType().Name;
        Details["error-message"] = ex.Message;
        Details["error-backtrace"] = ex.StackTrace ?? "<unknown>";
        Details["package-manager"] = "nuget";
        Details["job-id"] = jobId;
    }
}
