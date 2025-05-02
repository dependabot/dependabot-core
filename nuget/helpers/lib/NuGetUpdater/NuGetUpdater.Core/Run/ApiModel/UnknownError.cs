using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public record UnknownError : JobErrorBase
{
    [JsonIgnore]
    public Exception Exception { get; init; }

    public static readonly string UnknownStackTrace = "   <unknown>";

    public UnknownError(Exception ex, string jobId)
        : base("unknown_error")
    {
        Exception = ex;

        // The following object is parsed by the server and the `error-backtrace` property is expected to be a Ruby
        // stacktrace.  Since we're not in Ruby we can set an empty string there and append the .NET stacktrace to
        // the message.
        Details["error-class"] = ex.GetType().Name;
        Details["error-message"] = $"{ex.Message}\n{ex.StackTrace ?? UnknownStackTrace}";
        Details["error-backtrace"] = "";
        Details["package-manager"] = "nuget";
        Details["job-id"] = jobId;
    }
}
