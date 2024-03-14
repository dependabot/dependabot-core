using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Discover;

public partial class DiscoveryWorker
{
    public const string DiscoveryResultFileName = "./.dependabot/discovery.json";

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

    public async Task RunAsync(string repoRootPath, string workspacePath, string outputPath)
    {
        MSBuildHelper.RegisterMSBuild();

        if (!Path.IsPathRooted(workspacePath) || (!File.Exists(workspacePath) && !Directory.Exists(workspacePath)))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        var dotNetToolsJsonDiscovery = DotNetToolsJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);
        var globalJsonDiscovery = GlobalJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);

        WorkspaceType workspaceType = WorkspaceType.Unknown;
        ImmutableArray<ProjectDiscoveryResult> projectResults = [];

        if (File.Exists(workspacePath))
        {
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
        }
        else if (Directory.Exists(workspacePath))
        {
            workspaceType = WorkspaceType.Directory;
            projectResults = await RunForDirectoryAsnyc(repoRootPath, workspacePath);
        }
        else
        {
            _logger.Log($"Workspace path [{workspacePath}] does not exist.");
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

        await WriteResults(repoRootPath, outputPath, result);

        _logger.Log("Discovery complete.");

        _processedProjectPaths.Clear();
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForDirectoryAsnyc(string repoRootPath, string workspacePath)
    {
        _logger.Log($"Running for directory [{Path.GetRelativePath(repoRootPath, workspacePath)}]");
        var projectPaths = FindProjectFiles(workspacePath);
        if (projectPaths.IsEmpty)
        {
            _logger.Log("No project files found.");
            return [];
        }

        return await RunForProjectPathsAsync(repoRootPath, projectPaths);
    }

    private static ImmutableArray<string> FindProjectFiles(string workspacePath)
    {
        return Directory.EnumerateFiles(workspacePath, "*.??proj", SearchOption.AllDirectories)
            .Where(path =>
            {
                var extension = Path.GetExtension(path).ToLowerInvariant();
                return extension == ".csproj" || extension == ".fsproj" || extension == ".vbproj";
            })
            .ToImmutableArray();
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForSolutionAsync(string repoRootPath, string solutionPath)
    {
        _logger.Log($"Running for solution [{Path.GetRelativePath(repoRootPath, solutionPath)}]");
        if (!File.Exists(solutionPath))
        {
            _logger.Log($"File [{solutionPath}] does not exist.");
            return [];
        }

        var projectPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
        return await RunForProjectPathsAsync(repoRootPath, projectPaths);
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjFileAsync(string repoRootPath, string projFilePath)
    {
        _logger.Log($"Running for proj file [{Path.GetRelativePath(repoRootPath, projFilePath)}]");
        if (!File.Exists(projFilePath))
        {
            _logger.Log($"File [{projFilePath}] does not exist.");
            return [];
        }

        var projectPaths = MSBuildHelper.GetProjectPathsFromProject(projFilePath);
        return await RunForProjectPathsAsync(repoRootPath, projectPaths);
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjectAsync(string repoRootPath, string projectFilePath)
    {
        _logger.Log($"Running for project file [{Path.GetRelativePath(repoRootPath, projectFilePath)}]");
        if (!File.Exists(projectFilePath))
        {
            _logger.Log($"File [{projectFilePath}] does not exist.");
            return [];
        }

        var projectPaths = MSBuildHelper.GetProjectPathsFromProject(projectFilePath).Prepend(projectFilePath);
        return await RunForProjectPathsAsync(repoRootPath, projectPaths);
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjectPathsAsync(string repoRootPath, IEnumerable<string> projectFilePaths)
    {
        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.OrdinalIgnoreCase);
        foreach (var projectPath in projectFilePaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            if (!File.Exists(projectPath))
            {
                continue;
            }

            if (_processedProjectPaths.Contains(projectPath))
            {
                continue;
            }
            _processedProjectPaths.Add(projectPath);

            var relativeProjectPath = Path.GetRelativePath(repoRootPath, projectPath);
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

    private static async Task WriteResults(string repoRootPath, string outputPath, WorkspaceDiscoveryResult result)
    {
        var resultPath = Path.IsPathRooted(outputPath)
            ? outputPath
            : Path.GetFullPath(outputPath, repoRootPath);
        var resultDirectory = Path.GetDirectoryName(resultPath)!;
        if (!Directory.Exists(resultDirectory))
        {
            Directory.CreateDirectory(resultDirectory);
        }

        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        await File.WriteAllTextAsync(path: resultPath, resultJson);
    }
}
