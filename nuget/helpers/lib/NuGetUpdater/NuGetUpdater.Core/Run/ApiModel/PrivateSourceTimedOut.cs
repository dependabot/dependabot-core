namespace NuGetUpdater.Core.Run.ApiModel;

public record PrivateSourceTimedOut : JobErrorBase
{
    public PrivateSourceTimedOut(string url)
        : base("private_source_timed_out")
    {
        Details["source"] = url;
    }
}
