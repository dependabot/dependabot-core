using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

public partial class DiscoveryWorker
{
    public const string DiscoveryResultFileName = "./.dependabot/discovery.json";

    private readonly Logger _logger;
    private readonly HashSet<string> _processedProjectPaths = new(StringComparer.OrdinalIgnoreCase); private readonly HashSet<string> _restoredMSBuildSdks = new(StringComparer.OrdinalIgnoreCase);

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
        MSBuildHelper.RegisterMSBuild(Environment.CurrentDirectory, repoRootPath);

        // When running under unit tests, the workspace path may not be rooted.
        if (!Path.IsPathRooted(workspacePath) || !Directory.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }
        else if (workspacePath == "/")
        {
            workspacePath = repoRootPath;
        }

        DotNetToolsJsonDiscoveryResult? dotNetToolsJsonDiscovery = null;
        GlobalJsonDiscoveryResult? globalJsonDiscovery = null;
        DirectoryPackagesPropsDiscoveryResult? directoryPackagesPropsDiscovery = null;

        ImmutableArray<ProjectDiscoveryResult> projectResults = [];

        if (Directory.Exists(workspacePath))
        {
            _logger.Log($"Discovering build files in workspace [{workspacePath}].");

            dotNetToolsJsonDiscovery = DotNetToolsJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);
            globalJsonDiscovery = GlobalJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);

            if (globalJsonDiscovery is not null)
            {
                await TryRestoreMSBuildSdksAsync(repoRootPath, workspacePath, globalJsonDiscovery.Dependencies, _logger);
            }

            projectResults = await RunForDirectoryAsnyc(repoRootPath, workspacePath);

            directoryPackagesPropsDiscovery = DirectoryPackagesPropsDiscovery.Discover(repoRootPath, workspacePath, projectResults, _logger);

            if (directoryPackagesPropsDiscovery is not null)
            {
                projectResults = projectResults.Remove(projectResults.First(p => p.FilePath.Equals(directoryPackagesPropsDiscovery.FilePath, StringComparison.OrdinalIgnoreCase)));
            }
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
            Projects = projectResults.OrderBy(p => p.FilePath).ToImmutableArray(),
        };

        await WriteResults(repoRootPath, outputPath, result);

        _logger.Log("Discovery complete.");

        _processedProjectPaths.Clear();
    }

    /// <summary>
    /// Restores MSBuild SDKs from the given dependencies.
    /// </summary>
    /// <returns>Returns `true` when SDKs were restored successfully.</returns>
    private async Task<bool> TryRestoreMSBuildSdksAsync(string repoRootPath, string workspacePath, ImmutableArray<Dependency> dependencies, Logger logger)
    {
        var msbuildSdks = dependencies
            .Where(d => d.Type == DependencyType.MSBuildSdk && !string.IsNullOrEmpty(d.Version))
            .Where(d => !d.Name.Equals("Microsoft.NET.Sdk", StringComparison.OrdinalIgnoreCase))
            .Where(d => !_restoredMSBuildSdks.Contains($"{d.Name}/{d.Version}"))
            .ToImmutableArray();

        if (msbuildSdks.Length == 0)
        {
            return false;
        }

        var keys = msbuildSdks.Select(d => $"{d.Name}/{d.Version}");

        _restoredMSBuildSdks.AddRange(keys);

        _logger.Log($"  Restoring MSBuild SDKs: {string.Join(", ", keys)}");

        return await NuGetHelper.DownloadNuGetPackagesAsync(repoRootPath, workspacePath, msbuildSdks, logger);
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForDirectoryAsnyc(string repoRootPath, string workspacePath)
    {
        _logger.Log($"  Discovering projects beneath [{Path.GetRelativePath(repoRootPath, workspacePath)}].");
        var projectPaths = FindProjectFiles(workspacePath);
        if (projectPaths.IsEmpty)
        {
            _logger.Log("  No project files found.");
            return [];
        }

        return await RunForProjectPathsAsync(repoRootPath, workspacePath, projectPaths);
    }

    private static ImmutableArray<string> FindProjectFiles(string workspacePath)
    {
        return Directory.EnumerateFiles(workspacePath, "*.*proj", SearchOption.AllDirectories)
            .Where(path =>
            {
                var extension = Path.GetExtension(path).ToLowerInvariant();
                return extension == ".proj" || extension == ".csproj" || extension == ".fsproj" || extension == ".vbproj";
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

            // Determine if there were unrestored MSBuildSdks
            var msbuildSdks = projectResults.SelectMany(p => p.Dependencies.Where(d => d.Type == DependencyType.MSBuildSdk)).ToImmutableArray();
            if (msbuildSdks.Length > 0)
            {
                // If new SDKs were restored, then we need to rerun SdkProjectDiscovery.
                if (await TryRestoreMSBuildSdksAsync(repoRootPath, workspacePath, msbuildSdks, _logger))
                {
                    projectResults = await SdkProjectDiscovery.DiscoverAsync(repoRootPath, workspacePath, projectPath, _logger);
                }
            }

            foreach (var projectResult in projectResults)
            {
                if (results.ContainsKey(projectResult.FilePath))
                {
                    continue;
                }

                // If we had packages.config dependencies, merge them with the project dependencies
                if (projectResult.FilePath == relativeProjectPath && packagesConfigDependencies is not null)
                {
                    packagesConfigDependencies = packagesConfigDependencies.Value
                        .Select(d => d with { TargetFrameworks = projectResult.TargetFrameworks })
                        .ToImmutableArray();

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
