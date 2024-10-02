namespace NuGetUpdater.Core.Run.ApiModel;

public record PrivateSourceAuthenticationFailure : JobErrorBase
{
    public override string Type => "private_source_authentication_failure";
}
