using System.Net;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

public class UpdaterWorker : IUpdaterWorker
{
    private readonly ExperimentsManager _experimentsManager;
    private readonly ILogger _logger;
    private readonly HashSet<string> _processedProjectPaths = new(StringComparer.OrdinalIgnoreCase);

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public UpdaterWorker(ExperimentsManager experimentsManager, ILogger logger)
    {
        _experimentsManager = experimentsManager;
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive, string? resultOutputPath = null)
    {
        var result = await RunWithErrorHandlingAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
        if (resultOutputPath is { })
        {
            await WriteResultFile(result, resultOutputPath, _logger);
        }
    }

    // this is a convenient method for tests
    internal async Task<UpdateOperationResult> RunWithErrorHandlingAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        UpdateOperationResult result = new(); // assumed to be ok until proven otherwise
        try
        {
            result = await RunAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
        }
        catch (HttpRequestException ex)
        when (ex.StatusCode == HttpStatusCode.Unauthorized || ex.StatusCode == HttpStatusCode.Forbidden)
        {
            if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
            {
                workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
            }

            result = new()
            {
                ErrorType = ErrorType.AuthenticationFailure,
                ErrorDetails = "(" + string.Join("|", NuGetContext.GetPackageSourceUrls(workspacePath)) + ")",
            };
        }
        catch (MissingFileException ex)
        {
            result = new()
            {
                ErrorType = ErrorType.MissingFile,
                ErrorDetails = ex.FilePath,
            };
        }
        catch (UpdateNotPossibleException ex)
        {
            result = new()
            {
                ErrorType = ErrorType.UpdateNotPossible,
                ErrorDetails = ex.Dependencies,
            };
        }
        catch (Exception ex)
        {
            result = new()
            {
                ErrorType = ErrorType.Unknown,
                ErrorDetails = ex.ToString(),
            };
        }

        return result;
    }

    public async Task<UpdateOperationResult> RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        MSBuildHelper.RegisterMSBuild(Environment.CurrentDirectory, repoRootPath);

        if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        if (!isTransitive)
        {
            await DotNetToolsJsonUpdater.UpdateDependencyAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, _logger);
            await GlobalJsonUpdater.UpdateDependencyAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, _logger);
        }

        var extension = Path.GetExtension(workspacePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                await RunForSolutionAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
            case ".proj":
                await RunForProjFileAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                await RunForProjectAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
                break;
            default:
                _logger.Info($"File extension [{extension}] is not supported.");
                break;
        }

        _logger.Info("Update complete.");

        _processedProjectPaths.Clear();
        return new UpdateOperationResult();
    }

    internal static async Task WriteResultFile(UpdateOperationResult result, string resultOutputPath, ILogger logger)
    {
        logger.Info($"  Writing update result to [{resultOutputPath}].");

        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        await File.WriteAllTextAsync(resultOutputPath, resultJson);
    }

    private async Task RunForSolutionAsync(
        string repoRootPath,
        string solutionPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive)
    {
        _logger.Info($"Running for solution [{Path.GetRelativePath(repoRootPath, solutionPath)}]");
        var projectPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
        foreach (var projectPath in projectPaths)
        {
            await RunForProjectAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
        }
    }

    private async Task RunForProjFileAsync(
        string repoRootPath,
        string projFilePath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive)
    {
        _logger.Info($"Running for proj file [{Path.GetRelativePath(repoRootPath, projFilePath)}]");
        if (!File.Exists(projFilePath))
        {
            _logger.Info($"File [{projFilePath}] does not exist.");
            return;
        }

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

    private async Task RunForProjectAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive)
    {
        _logger.Info($"Running for project file [{Path.GetRelativePath(repoRootPath, projectPath)}]");
        if (!File.Exists(projectPath))
        {
            _logger.Info($"File [{projectPath}] does not exist.");
            return;
        }

        var projectFilePaths = MSBuildHelper.GetProjectPathsFromProject(projectPath);
        foreach (var projectFullPath in projectFilePaths.Concat([projectPath]))
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectFullPath))
            {
                await RunUpdaterAsync(repoRootPath, projectFullPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
            }
        }
    }

    private async Task RunUpdaterAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive)
    {
        if (_processedProjectPaths.Contains(projectPath))
        {
            return;
        }

        _processedProjectPaths.Add(projectPath);

        _logger.Info($"Updating project [{projectPath}]");

        var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(projectPath, ProjectHelper.PathFormat.Full);
        var packagesConfigFullPath = additionalFiles.Where(p => Path.GetFileName(p).Equals(ProjectHelper.PackagesConfigFileName, StringComparison.OrdinalIgnoreCase)).FirstOrDefault();
        if (packagesConfigFullPath is not null)
        {
            await PackagesConfigUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, packagesConfigFullPath, _logger);
        }

        // Some repos use a mix of packages.config and PackageReference
        await PackageReferenceUpdater.UpdateDependencyAsync(repoRootPath, projectPath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive, _experimentsManager, _logger);

        // Update lock file if exists
        var packagesLockFullPath = additionalFiles.Where(p => Path.GetFileName(p).Equals(ProjectHelper.PackagesLockJsonFileName, StringComparison.OrdinalIgnoreCase)).FirstOrDefault();
        if (packagesLockFullPath is not null)
        {
            await LockFileUpdater.UpdateLockFileAsync(repoRootPath, projectPath, _logger);
        }
    }
}
