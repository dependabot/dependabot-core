using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Discover;

public partial class DiscoveryWorker
{
    public const string DiscoveryResultFileName = ".dependabot/discovery.json";

    private readonly Logger _logger;
    private readonly HashSet<string> _processedProjectPaths = new(StringComparer.OrdinalIgnoreCase);

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public DiscoveryWorker(Logger logger)
    {
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string workspacePath)
    {
        MSBuildHelper.RegisterMSBuild();

        if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        var dotNetToolsJsonDiscovery = DotNetToolsJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);
        var globalJsonDiscovery = GlobalJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);

        WorkspaceType workspaceType = WorkspaceType.Unknown;
        ImmutableArray<ProjectDiscoveryResult> projectResults = [];

        var extension = Path.GetExtension(workspacePath).ToLowerInvariant();
        switch (extension)
        {
            case ".sln":
                workspaceType = WorkspaceType.Solution;
                projectResults = await RunForSolutionAsync(repoRootPath, workspacePath);
                break;
            case ".proj":
                workspaceType = WorkspaceType.DirsProj;
                projectResults = await RunForProjFileAsync(repoRootPath, workspacePath);
                break;
            case ".csproj":
            case ".fsproj":
            case ".vbproj":
                workspaceType = WorkspaceType.Project;
                projectResults = await RunForProjectAsync(repoRootPath, workspacePath);
                break;
            default:
                _logger.Log($"File extension [{extension}] is not supported.");
                break;
        }

        var directoryPackagesPropsDiscovery = DirectoryPackagesPropsDiscovery.Discover(repoRootPath, workspacePath, projectResults, _logger);

        var result = new WorkspaceDiscoveryResult
        {
            FilePath = Path.GetRelativePath(repoRootPath, workspacePath),
            TargetFrameworks = projectResults
                .SelectMany(p => p.TargetFrameworks)
                .Distinct()
                .ToImmutableArray(),
            Type = workspaceType,
            DotNetToolsJson = dotNetToolsJsonDiscovery,
            GlobalJson = globalJsonDiscovery,
            DirectoryPackagesProps = directoryPackagesPropsDiscovery,
            Projects = projectResults,
        };

        await WriteResults(repoRootPath, result);

        _logger.Log("Discovery complete.");

        _processedProjectPaths.Clear();
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForSolutionAsync(string repoRootPath, string solutionPath)
    {
        _logger.Log($"Running for solution [{Path.GetRelativePath(repoRootPath, solutionPath)}]");
        if (!File.Exists(solutionPath))
        {
            _logger.Log($"File [{solutionPath}] does not exist.");
            return [];
        }

        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.OrdinalIgnoreCase);
        var projectPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
        foreach (var projectPath in projectPaths)
        {
            var projectResults = await RunForProjectAsync(repoRootPath, projectPath);
            foreach (var projectResult in projectResults)
            {
                if (results.ContainsKey(projectResult.FilePath))
                {
                    continue;
                }

                results[projectResult.FilePath] = projectResult;
            }
        }

        return [.. results.Values];
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjFileAsync(string repoRootPath, string projFilePath)
    {
        _logger.Log($"Running for proj file [{Path.GetRelativePath(repoRootPath, projFilePath)}]");
        if (!File.Exists(projFilePath))
        {
            _logger.Log($"File [{projFilePath}] does not exist.");
            return [];
        }

        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.OrdinalIgnoreCase);
        var projectPaths = MSBuildHelper.GetProjectPathsFromProject(projFilePath);
        foreach (var projectPath in projectPaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (File.Exists(projectPath))
            {
                var projectResults = await RunForProjectAsync(repoRootPath, projectPath);
                foreach (var projectResult in projectResults)
                {
                    if (results.ContainsKey(projectResult.FilePath))
                    {
                        continue;
                    }

                    results[projectResult.FilePath] = projectResult;
                }
            }
        }

        return [.. results.Values];
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjectAsync(string repoRootPath, string projectFilePath)
    {
        var relativeProjectPath = Path.GetRelativePath(repoRootPath, projectFilePath);
        _logger.Log($"Running for project file [{relativeProjectPath}]");
        if (!File.Exists(projectFilePath))
        {
            _logger.Log($"File [{projectFilePath}] does not exist.");
            return [];
        }

        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.OrdinalIgnoreCase);
        var projectPaths = MSBuildHelper.GetProjectPathsFromProject(projectFilePath);
        foreach (var projectPath in projectPaths.Prepend(projectFilePath))
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (!File.Exists(projectPath))
            {
                continue;
            }

            var packagesConfigDependencies = PackagesConfigDiscovery.Discover(repoRootPath, projectPath, _logger)
                    ?.Dependencies;

            var projectResults = await SdkProjectDiscovery.DiscoverAsync(repoRootPath, projectPath, _logger);
            foreach (var projectResult in projectResults)
            {
                if (results.ContainsKey(projectResult.FilePath))
                {
                    continue;
                }

                // If we had packages.config dependencies, merge them with the project dependencies
                if (projectResult.FilePath == relativeProjectPath && packagesConfigDependencies is not null)
                {
                    results[projectResult.FilePath] = projectResult with
                    {
                        Dependencies = [.. projectResult.Dependencies, .. packagesConfigDependencies],
                    };
                }
                else
                {
                    results[projectResult.FilePath] = projectResult;
                }
            }
        }

        return [.. results.Values];
    }

    private static async Task WriteResults(string repoRootPath, WorkspaceDiscoveryResult result)
    {
        var resultPath = Path.GetFullPath(DiscoveryResultFileName, repoRootPath);
        var resultDirectory = Path.GetDirectoryName(resultPath)!;
        if (!Directory.Exists(resultDirectory))
        {
            Directory.CreateDirectory(resultDirectory);
        }

        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        await File.WriteAllTextAsync(path: resultPath, resultJson);
    }
}
