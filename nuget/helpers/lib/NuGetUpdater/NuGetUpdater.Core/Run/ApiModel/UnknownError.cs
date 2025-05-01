using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public record UnknownError : JobErrorBase
{
    [JsonIgnore]
    public Exception Exception { get; init; }

    public UnknownError(Exception ex, string jobId)
        : base("unknown_error")
    {
        Exception = ex;
        Details["error-class"] = ex.GetType().Name;
        Details["error-message"] = ex.Message;
        Details["error-backtrace"] = ex.StackTrace ?? "<unknown>";
        Details["package-manager"] = "nuget";
        Details["job-id"] = jobId;
    }
}
