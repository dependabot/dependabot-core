using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record WorkspaceDiscoveryResult : IDiscoveryResult
{
    public required string FilePath { get; init; }
    public WorkspaceType Type { get; init; }
    public ImmutableArray<string> TargetFrameworks { get; init; }
    public ImmutableArray<ProjectDiscoveryResult> Projects { get; init; }
    public DirectoryPackagesPropsDiscoveryResult? DirectoryPackagesProps { get; init; }
    public GlobalJsonDiscoveryResult? GlobalJson { get; init; }
    public DotNetToolsJsonDiscoveryResult? DotNetToolsJson { get; init; }
}

public enum WorkspaceType
{
    Unknown,
    Directory,
    Solution,
    DirsProj,
    Project,
}
