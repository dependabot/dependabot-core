using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record WorkspaceDiscoveryResult : NativeResult
{
    public required string Path { get; init; }
    public bool IsSuccess { get; init; } = true;
    public ImmutableArray<ProjectDiscoveryResult> Projects { get; init; }
    public GlobalJsonDiscoveryResult? GlobalJson { get; init; }
    public DotNetToolsJsonDiscoveryResult? DotNetToolsJson { get; init; }

    public ProjectDiscoveryResult? GetProjectDiscoveryFromPath(string repoPath)
    {
        var projectDiscovery = Projects.FirstOrDefault(p => System.IO.Path.Join(Path, p.FilePath).FullyNormalizedRootedPath().Equals(repoPath, StringComparison.OrdinalIgnoreCase));
        return projectDiscovery;
    }
}
