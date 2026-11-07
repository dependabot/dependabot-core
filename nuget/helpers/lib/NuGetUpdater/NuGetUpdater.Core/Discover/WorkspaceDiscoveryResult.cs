using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public sealed record WorkspaceDiscoveryResult : NativeResult
{
    public required string Path { get; init; }
    public bool IsSuccess { get; init; } = true;
    public ImmutableArray<ProjectDiscoveryResult> Projects { get; init; }
    public GlobalJsonDiscoveryResult? GlobalJson { get; init; }
    public DotNetToolsJsonDiscoveryResult? DotNetToolsJson { get; init; }

    // when the workspace directly contains a solution file, this is the directory that was used to fake the MSBuild
    // `SolutionDir` property during discovery; it is `null` when no solution file was present
    public string? SolutionDirectory { get; init; }

    public ProjectDiscoveryResult? GetProjectDiscoveryFromPath(string repoPath)
    {
        var projectDiscovery = Projects.FirstOrDefault(p => System.IO.Path.Join(Path, p.FilePath).FullyNormalizedRootedPath().Equals(repoPath, StringComparison.OrdinalIgnoreCase));
        return projectDiscovery;
    }

    public ProjectDiscoveryResult? GetProjectDiscoveryFromFullPath(DirectoryInfo repoContentsPath, FileInfo projectPath)
    {
        var projectDiscovery = Projects.FirstOrDefault(p => System.IO.Path.Join(repoContentsPath.FullName, Path, p.FilePath).FullyNormalizedRootedPath().Equals(projectPath.FullName.FullyNormalizedRootedPath(), StringComparison.OrdinalIgnoreCase));
        return projectDiscovery;
    }
}
