namespace NuGetUpdater.Core.Run.ApiModel;

public record BadRequirement : JobErrorBase
{
    public BadRequirement(string details)
        : base("illformed_requirement")
    {
        Details["message"] = details;
    }
}
