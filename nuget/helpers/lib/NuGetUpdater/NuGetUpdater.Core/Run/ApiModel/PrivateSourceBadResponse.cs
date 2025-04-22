namespace NuGetUpdater.Core.Run.ApiModel;

public record PrivateSourceBadResponse : JobErrorBase
{
    public PrivateSourceBadResponse(string[] urls)
        : base("private_source_bad_response")
    {
        Details["source"] = $"({string.Join("|", urls)})";
    }
}
