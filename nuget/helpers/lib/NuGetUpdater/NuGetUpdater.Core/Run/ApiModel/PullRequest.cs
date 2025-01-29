using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.ApiModel;

public record PullRequest
{
    public required string DependencyName { get; init; }
    public required NuGetVersion DependencyVersion { get; init; }
    public bool DependencyRemoved { get; init; } = false;
    public string? Directory { get; init; } = null;
}
