namespace NuGetUpdater.Core.Run.ApiModel;

public sealed class JobSource
{
    public required string Provider { get; init; }
    public required string Repo { get; init; }
    public string? Branch { get; init; } = null;
    public string? Commit { get; init; } = null;
    public string? Directory { get; init; } = null;
    public string[]? Directories { get; init; } = null;
    public string? Hostname { get; init; } = null;
    public string? ApiEndpoint { get; init; } = null;
}
