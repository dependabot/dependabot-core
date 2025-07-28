using System.Collections.Immutable;

using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Core.DependencySolver;

public class MSBuildDependencySolver : IDependencySolver
{
    private readonly DirectoryInfo _repoContentsPath;
    private readonly FileInfo _projectPath;
    private readonly ILogger _logger;

    public MSBuildDependencySolver(DirectoryInfo repoContentsPath, FileInfo projectPath, ILogger logger)
    {
        _repoContentsPath = repoContentsPath;
        _projectPath = projectPath;
        _logger = logger;
    }

    public async Task<ImmutableArray<Dependency>?> SolveAsync(ImmutableArray<Dependency> existingTopLevelDependencies, ImmutableArray<Dependency> desiredDependencies, string targetFramework)
    {
        var projectExtension = _projectPath.Extension.ToLowerInvariant();
        if (!XmlFileWriter.SupportedProjectFileExtensions.Contains(projectExtension))
        {
            // not a real project, nothing to solve.
            return null;
        }

        var result = await MSBuildHelper.ResolveDependencyConflicts(
            _repoContentsPath.FullName,
            _projectPath.FullName,
            targetFramework,
            existingTopLevelDependencies,
            desiredDependencies,
            _logger);
        return result;
    }
}
