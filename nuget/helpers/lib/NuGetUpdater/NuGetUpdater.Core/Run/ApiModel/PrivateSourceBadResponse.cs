using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public record PrivateSourceBadResponse : JobErrorBase
{
    [JsonIgnore]
    public string Message { get; }

    public PrivateSourceBadResponse(string[] urls, string message)
        : base("private_source_bad_response")
    {
        Details["source"] = $"({string.Join("|", urls)})";
        Message = message;
    }

    public override string GetReport()
    {
        var report = base.GetReport();

        // this extra info isn't part of the reported shape but is useful to have in the log
        var fullReport = string.Concat(report, "\n", $"- message: {Message}");
        return fullReport;
    }
}
