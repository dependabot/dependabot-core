using System.IO;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

public partial class UpdaterWorker
{
    private readonly Logger _logger;

    public UpdaterWorker(Logger logger)
    {
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string filePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        MSBuildHelper.RegisterMSBuild();

        if (!Path.IsPathRooted(filePath) || !File.Exists(filePath))
        {
            filePath = Path.GetFullPath(Path.Join(repoRootPath, filePath));
        }

        if (!isTransitive)
        {
            await GlobalJsonUpdater.UpdateDependencyAsync(repoRootPath, dependencyName, previousDependencyVersion, newDependencyVersion, _logger);
            await DotNetToolsJsonUpdater.UpdateDependencyAsync(repoRootPath, dependencyName, previousDependencyVersion, newDependencyVersion, _logger);
        }

        var extension = Path.GetExtension(filePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                await RunForSolutionAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
            case ".proj":
                await RunForProjFileAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                await RunForProjectAsync(repoRootPath, filePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
        }
    }

    private async Task RunForSolutionAsync(string repoRootPath, string solutionPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        _logger.Log($"Running for solution [{Path.GetRelativePath(repoRootPath, solutionPath)}]");
        var projectPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
        foreach (var projectPath in projectPaths)
        {
            await RunForProjectAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
        }
    }

    private async Task RunForProjFileAsync(string repoRootPath, string projFilePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        _logger.Log($"Running for proj file [{Path.GetRelativePath(repoRootPath, projFilePath)}]");
        var projectFilePaths = MSBuildHelper.GetProjectPathsFromProject(projFilePath);
        foreach (var projectFullPath in projectFilePaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectFullPath))
            {
                await RunForProjectAsync(repoRootPath, projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
            }
        }
    }

    private async Task RunForProjectAsync(string repoRootPath, string projectPath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        _logger.Log($"Running for project [{projectPath}]");

        if (NuGetHelper.HasProjectConfigFile(projectPath))
        {
            await PackagesConfigUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive, _logger);
        }

        // Some repos use a mix of packages.config and PackageReference
        await SdkPackageUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive, _logger);

        _logger.Log("Update complete.");
    }
}
