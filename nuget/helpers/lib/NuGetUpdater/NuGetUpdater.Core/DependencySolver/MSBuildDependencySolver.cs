using System.Collections.Immutable;

namespace NuGetUpdater.Core.DependencySolver;

public class MSBuildDependencySolver : IDependencySolver
{
    private readonly DirectoryInfo _repoContentsPath;
    private readonly FileInfo _projectPath;
    private readonly ExperimentsManager _experimentsManager;
    private readonly ILogger _logger;

    public MSBuildDependencySolver(DirectoryInfo repoContentsPath, FileInfo projectPath, ExperimentsManager experimentsManager, ILogger logger)
    {
        _repoContentsPath = repoContentsPath;
        _projectPath = projectPath;
        _experimentsManager = experimentsManager;
        _logger = logger;
    }

    public async Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, string targetFramework)
    {
        var result = await MSBuildHelper.ResolveDependencyConflicts(
            _repoContentsPath.FullName,
            _projectPath.FullName,
            targetFramework,
            existingTopLevelDependencies,
            desiredDependencies,
            _experimentsManager,
            _logger);
        return result;
    }
}
