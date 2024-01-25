using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

public class UpdaterWorker
{
    private readonly Logger _logger;
    private readonly HashSet<string> _processedGlobalJsonPaths = new(StringComparer.OrdinalIgnoreCase);

    public UpdaterWorker(Logger logger)
    {
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string workspacePath, IReadOnlyCollection<DependencyRequest> dependencies)
    {
        MSBuildHelper.RegisterMSBuild();

        if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        foreach (DependencyRequest dependency in dependencies)
        {
            if (!dependency.IsTransitive)
            {
                await DotNetToolsJsonUpdater.UpdateDependencyAsync(repoRootPath, workspacePath, dependency.Name, dependency.PreviousVersion, dependency.NewVersion, _logger);
            }
        }

        var extension = Path.GetExtension(workspacePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                await RunForSolutionAsync(repoRootPath, workspacePath, dependencies);
                break;
            case ".proj":
                await RunForProjFileAsync(repoRootPath, workspacePath, dependencies);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                await RunForProjectAsync(repoRootPath, workspacePath, dependencies);
                break;
            default:
                _logger.Log($"File extension [{extension}] is not supported.");
                break;
        }

        _processedGlobalJsonPaths.Clear();
    }

    private async Task RunForSolutionAsync(
        string repoRootPath,
        string solutionPath,
        IReadOnlyCollection<DependencyRequest> dependencies)
    {
        _logger.Log($"Running for solution [{Path.GetRelativePath(repoRootPath, solutionPath)}]");
        var projectPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
        foreach (var projectPath in projectPaths)
        {
            await RunForProjectAsync(repoRootPath, projectPath, dependencies);
        }
    }

    private async Task RunForProjFileAsync(
        string repoRootPath,
        string projFilePath,
        IReadOnlyCollection<DependencyRequest> dependencies)
    {
        _logger.Log($"Running for proj file [{Path.GetRelativePath(repoRootPath, projFilePath)}]");
        if (!File.Exists(projFilePath))
        {
            _logger.Log($"File [{projFilePath}] does not exist.");
            return;
        }

        var projectFilePaths = MSBuildHelper.GetProjectPathsFromProject(projFilePath);
        foreach (var projectFullPath in projectFilePaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectFullPath))
            {
                await RunForProjectAsync(repoRootPath, projectFullPath, dependencies);
            }
        }
    }

    private async Task RunForProjectAsync(
        string repoRootPath, string projectPath, IReadOnlyCollection<DependencyRequest> dependencies
    )
    {
        _logger.Log($"Running for project [{projectPath}]");

        foreach (DependencyRequest dependency in dependencies)
        {
            if (!dependency.IsTransitive
                && MSBuildHelper.GetGlobalJsonPath(repoRootPath, projectPath) is { } globalJsonPath
                && !_processedGlobalJsonPaths.Contains(globalJsonPath))
            {
                _processedGlobalJsonPaths.Add(globalJsonPath);
                await GlobalJsonUpdater.UpdateDependencyAsync(repoRootPath, globalJsonPath, dependency.Name, dependency.PreviousVersion, dependency.NewVersion, _logger);
            }
        }

        if (NuGetHelper.HasProjectConfigFile(projectPath))
        {
            foreach (DependencyRequest dependency in dependencies)
            {
                await PackagesConfigUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependency.Name, dependency.PreviousVersion, dependency.NewVersion, dependency.IsTransitive, _logger);
            }
        }

        // Some repos use a mix of packages.config and PackageReference
        await SdkPackageUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive, _logger);

        _logger.Log("Update complete.");
    }
}
