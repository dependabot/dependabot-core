namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record JobFile
{
    public required Job Job { get; init; }
}
