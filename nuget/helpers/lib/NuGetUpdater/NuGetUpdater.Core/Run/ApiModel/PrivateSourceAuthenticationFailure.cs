namespace NuGetUpdater.Core.Run.ApiModel;

public record PrivateSourceAuthenticationFailure : JobErrorBase
{
    public PrivateSourceAuthenticationFailure(string[] urls)
        : base("private_source_authentication_failure")
    {
        Details["source"] = $"({string.Join("|", urls)})";
    }
}
