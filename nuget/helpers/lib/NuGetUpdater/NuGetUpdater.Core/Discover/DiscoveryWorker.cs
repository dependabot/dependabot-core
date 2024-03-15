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

        // When running under unit tests, the workspace path may not be rooted.
        if (!Path.IsPathRooted(workspacePath) || !Directory.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        DotNetToolsJsonDiscoveryResult? dotNetToolsJsonDiscovery = null;
        GlobalJsonDiscoveryResult? globalJsonDiscovery = null;
        DirectoryPackagesPropsDiscoveryResult? directoryPackagesPropsDiscovery = null;

        ImmutableArray<ProjectDiscoveryResult> projectResults = [];

        if (Directory.Exists(workspacePath))
        {
            dotNetToolsJsonDiscovery = DotNetToolsJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);
            globalJsonDiscovery = GlobalJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);

            projectResults = await RunForDirectoryAsnyc(repoRootPath, workspacePath);

            directoryPackagesPropsDiscovery = DirectoryPackagesPropsDiscovery.Discover(repoRootPath, workspacePath, projectResults, _logger);
        }
        else
        {
            _logger.Log($"Workspace path [{workspacePath}] does not exist.");
        }

        var result = new WorkspaceDiscoveryResult
        {
            FilePath = repoRootPath != workspacePath ? Path.GetRelativePath(repoRootPath, workspacePath) : string.Empty,
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

        return await RunForProjectPathsAsync(repoRootPath, workspacePath, projectPaths);
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

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjectPathsAsync(string repoRootPath, string workspacePath, IEnumerable<string> projectPaths)
    {
        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.OrdinalIgnoreCase);
        foreach (var projectPath in projectPaths)
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

            var relativeProjectPath = Path.GetRelativePath(workspacePath, projectPath);
            var packagesConfigDependencies = PackagesConfigDiscovery.Discover(workspacePath, projectPath, _logger)
                    ?.Dependencies;

            var projectResults = await SdkProjectDiscovery.DiscoverAsync(repoRootPath, workspacePath, projectPath, _logger);
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
