namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record AllowedUpdate
{
    public string UpdateType { get; init; } = "all";
}
