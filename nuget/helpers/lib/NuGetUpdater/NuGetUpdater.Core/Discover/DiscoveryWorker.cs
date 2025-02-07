using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using Microsoft.Build.Construction;
using Microsoft.Build.Definition;
using Microsoft.Build.Evaluation;
using Microsoft.Build.Exceptions;

using NuGet.Frameworks;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

public partial class DiscoveryWorker : IDiscoveryWorker
{
    public const string DiscoveryResultFileName = "./.dependabot/discovery.json";

    private readonly string _jobId;
    private readonly ExperimentsManager _experimentsManager;
    private readonly ILogger _logger;
    private readonly HashSet<string> _processedProjectPaths = new(StringComparer.Ordinal); private readonly HashSet<string> _restoredMSBuildSdks = new(StringComparer.OrdinalIgnoreCase);

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public DiscoveryWorker(string jobId, ExperimentsManager experimentsManager, ILogger logger)
    {
        _jobId = jobId;
        _experimentsManager = experimentsManager;
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string workspacePath, string outputPath)
    {
        var result = await RunWithErrorHandlingAsync(repoRootPath, workspacePath);
        await WriteResultsAsync(repoRootPath, outputPath, result);
    }

    internal async Task<WorkspaceDiscoveryResult> RunWithErrorHandlingAsync(string repoRootPath, string workspacePath)
    {
        WorkspaceDiscoveryResult result;
        try
        {
            result = await RunAsync(repoRootPath, workspacePath);
        }
        catch (Exception ex)
        {
            result = new WorkspaceDiscoveryResult
            {
                Error = JobErrorBase.ErrorFromException(ex, _jobId, PathHelper.JoinPath(repoRootPath, workspacePath)),
                Path = workspacePath,
                Projects = [],
            };
        }

        return result;
    }

    public async Task<WorkspaceDiscoveryResult> RunAsync(string repoRootPath, string workspacePath)
    {
        MSBuildHelper.RegisterMSBuild(repoRootPath, workspacePath);

        // the `workspacePath` variable is relative to a repository root, so a rooted path actually isn't rooted; the
        // easy way to deal with this is to just trim the leading "/" if it exists
        if (workspacePath.StartsWith("/"))
        {
            workspacePath = workspacePath[1..];
        }

        string initialWorkspacePath = workspacePath;
        workspacePath = Path.Combine(repoRootPath, workspacePath);

        DotNetToolsJsonDiscoveryResult? dotNetToolsJsonDiscovery = null;
        GlobalJsonDiscoveryResult? globalJsonDiscovery = null;

        ImmutableArray<ProjectDiscoveryResult> projectResults = [];
        WorkspaceDiscoveryResult result;

        if (Directory.Exists(workspacePath))
        {
            _logger.Info($"Discovering build files in workspace [{workspacePath}].");

            dotNetToolsJsonDiscovery = DotNetToolsJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);
            globalJsonDiscovery = GlobalJsonDiscovery.Discover(repoRootPath, workspacePath, _logger);

            if (globalJsonDiscovery is not null)
            {
                await TryRestoreMSBuildSdksAsync(repoRootPath, workspacePath, globalJsonDiscovery.Dependencies, _logger);
            }

            // this next line should throw or something
            projectResults = await RunForDirectoryAsync(repoRootPath, workspacePath);
        }
        else
        {
            _logger.Info($"Workspace path [{workspacePath}] does not exist.");
        }

        //if any projectResults are not successful, return a failed result
        if (projectResults.Any(p => p.IsSuccess == false))
        {
            var failedProjectResult = projectResults.Where(p => p.IsSuccess == false).First();
            var failedDiscoveryResult = new WorkspaceDiscoveryResult
            {
                Path = initialWorkspacePath,
                DotNetToolsJson = null,
                GlobalJson = null,
                Projects = projectResults.Where(p => p.IsSuccess).OrderBy(p => p.FilePath).ToImmutableArray(),
                Error = failedProjectResult.Error,
                IsSuccess = false,
            };

            return failedDiscoveryResult;
        }

        result = new WorkspaceDiscoveryResult
        {
            Path = initialWorkspacePath,
            DotNetToolsJson = dotNetToolsJsonDiscovery,
            GlobalJson = globalJsonDiscovery,
            Projects = projectResults.OrderBy(p => p.FilePath).ToImmutableArray(),
        };

        _logger.Info("Discovery complete.");
        _processedProjectPaths.Clear();

        return result;
    }

    /// <summary>
    /// Restores MSBuild SDKs from the given dependencies.
    /// </summary>
    /// <returns>Returns `true` when SDKs were restored successfully.</returns>
    private async Task<bool> TryRestoreMSBuildSdksAsync(string repoRootPath, string workspacePath, ImmutableArray<Dependency> dependencies, ILogger logger)
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

        _logger.Info($"  Restoring MSBuild SDKs: {string.Join(", ", keys)}");

        return await NuGetHelper.DownloadNuGetPackagesAsync(repoRootPath, workspacePath, msbuildSdks, _experimentsManager, logger);
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForDirectoryAsync(string repoRootPath, string workspacePath)
    {
        _logger.Info($"  Discovering projects beneath [{Path.GetRelativePath(repoRootPath, workspacePath)}].");
        var entryPoints = FindEntryPoints(workspacePath);
        ImmutableArray<string> projects;
        try
        {
            projects = ExpandEntryPointsIntoProjects(entryPoints);
        }
        catch (InvalidProjectFileException e)
        {
            var invalidProjectFile = Path.GetRelativePath(workspacePath, e.ProjectFile).NormalizePathToUnix();

            _logger.Info("Error encountered during discovery: " + e.Message);
            return [new ProjectDiscoveryResult
            {
                FilePath = invalidProjectFile,
                Dependencies = ImmutableArray<Dependency>.Empty,
                ImportedFiles = ImmutableArray<string>.Empty,
                AdditionalFiles = ImmutableArray<string>.Empty,
                IsSuccess = false,
                Error = new DependencyFileNotParseable(invalidProjectFile),
            }];
        }
        if (projects.IsEmpty)
        {
            _logger.Info("  No project files found.");
            return [];
        }

        return await RunForProjectPathsAsync(repoRootPath, workspacePath, projects);
    }

    private static ImmutableArray<string> FindEntryPoints(string workspacePath)
    {
        return Directory.EnumerateFiles(workspacePath)
            .Where(path =>
            {
                string extension = Path.GetExtension(path).ToLowerInvariant();
                switch (extension)
                {
                    case ".sln":
                    case ".proj":
                    case ".csproj":
                    case ".fsproj":
                    case ".vbproj":
                        return true;
                    default:
                        return false;
                }
            })
            .ToImmutableArray();
    }

    private static ImmutableArray<string> ExpandEntryPointsIntoProjects(IEnumerable<string> entryPoints)
    {
        HashSet<string> expandedProjects = new();
        HashSet<string> seenProjects = new();
        Stack<string> filesToExpand = new(entryPoints);
        while (filesToExpand.Count > 0)
        {
            string candidateEntryPoint = filesToExpand.Pop();
            if (seenProjects.Add(candidateEntryPoint))
            {
                string extension = Path.GetExtension(candidateEntryPoint).ToLowerInvariant();
                if (extension == ".sln")
                {
                    SolutionFile solution = SolutionFile.Parse(candidateEntryPoint);
                    foreach (ProjectInSolution project in solution.ProjectsInOrder)
                    {
                        filesToExpand.Push(project.AbsolutePath);
                    }
                }
                else if (extension == ".proj")
                {
                    IEnumerable<string> foundProjects = ExpandItemGroupFilesFromProject(candidateEntryPoint, "ProjectFile", "ProjectReference");
                    foreach (string foundProject in foundProjects)
                    {
                        filesToExpand.Push(foundProject);
                    }
                }
                else
                {
                    switch (extension)
                    {
                        case ".csproj":
                        case ".fsproj":
                        case ".vbproj":
                            // keep this project and check for references
                            expandedProjects.Add(candidateEntryPoint);
                            IEnumerable<string> referencedProjects = ExpandItemGroupFilesFromProject(candidateEntryPoint, "ProjectReference");
                            foreach (string referencedProject in referencedProjects)
                            {
                                filesToExpand.Push(referencedProject);
                            }
                            break;
                        default:
                            continue;
                    }
                }
            }
        }

        var result = expandedProjects.OrderBy(p => p).ToImmutableArray();
        return result;
    }

    private static IEnumerable<string> ExpandItemGroupFilesFromProject(string projectPath, params string[] itemTypes)
    {
        if (!File.Exists(projectPath))
        {
            return [];
        }

        using ProjectCollection projectCollection = new();
        Project project = Project.FromFile(projectPath, new ProjectOptions
        {
            LoadSettings = ProjectLoadSettings.IgnoreMissingImports | ProjectLoadSettings.IgnoreEmptyImports | ProjectLoadSettings.IgnoreInvalidImports,
            ProjectCollection = projectCollection,
        });

        HashSet<string> allowableItemTypes = new(itemTypes, StringComparer.OrdinalIgnoreCase);
        List<ProjectItem> projectItems = project.Items.Where(i => allowableItemTypes.Contains(i.ItemType)).ToList();
        string projectDir = Path.GetDirectoryName(projectPath)!;
        HashSet<string> seenItems = new(StringComparer.OrdinalIgnoreCase);
        List<string> foundItems = new();
        foreach (ProjectItem projectItem in projectItems)
        {
            // referenced projects commonly use the Windows-style directory separator which can cause problems on Unix
            // but Windows is able to handle a Unix-style path, so we normalize everything to that then normalize again
            // with regards to relative paths, e.g., "some/path/" + "..\other\file" => "some/other/file"
            string referencedProjectPath = Path.Join(projectDir, projectItem.EvaluatedInclude.NormalizePathToUnix());
            string normalizedReferenceProjectPath = new FileInfo(referencedProjectPath).FullName;
            if (seenItems.Add(normalizedReferenceProjectPath))
            {
                foundItems.Add(normalizedReferenceProjectPath);
            }
        }

        return foundItems;
    }

    private async Task<ImmutableArray<ProjectDiscoveryResult>> RunForProjectPathsAsync(string repoRootPath, string workspacePath, IEnumerable<string> projectPaths)
    {
        var results = new Dictionary<string, ProjectDiscoveryResult>(StringComparer.Ordinal);
        foreach (var projectPath in projectPaths)
        {
            // If there is some MSBuild logic that needs to run to fully resolve the path skip the project
            // Ensure file existence is checked case-insensitively
            var actualProjectPaths = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(projectPath, repoRootPath);

            if (actualProjectPaths == null)
            {
                continue;
            }

            foreach (var actualProjectPath in actualProjectPaths)
            {
                if (_processedProjectPaths.Contains(actualProjectPath))
                {
                    continue;
                }

                _processedProjectPaths.Add(actualProjectPath);

                var relativeProjectPath = Path.GetRelativePath(workspacePath, actualProjectPath).NormalizePathToUnix();
                var packagesConfigResult = await PackagesConfigDiscovery.Discover(repoRootPath, workspacePath, actualProjectPath, _experimentsManager, _logger);
                var projectResults = await SdkProjectDiscovery.DiscoverAsync(repoRootPath, workspacePath, actualProjectPath, _experimentsManager, _logger);

                // Determine if there were unrestored MSBuildSdks
                var msbuildSdks = projectResults.SelectMany(p => p.Dependencies.Where(d => d.Type == DependencyType.MSBuildSdk)).ToImmutableArray();
                if (msbuildSdks.Length > 0)
                {
                    // If new SDKs were restored, then we need to rerun SdkProjectDiscovery.
                    if (await TryRestoreMSBuildSdksAsync(repoRootPath, workspacePath, msbuildSdks, _logger))
                    {
                        projectResults = await SdkProjectDiscovery.DiscoverAsync(repoRootPath, workspacePath, actualProjectPath, _experimentsManager, _logger);
                    }
                }

                foreach (var projectResult in projectResults)
                {
                    if (results.ContainsKey(projectResult.FilePath))
                    {
                        continue;
                    }

                    // If we had packages.config dependencies, merge them with the project dependencies
                    if (projectResult.FilePath == relativeProjectPath && packagesConfigResult is not null)
                    {
                        var packagesConfigDependencies = packagesConfigResult.Dependencies
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

                if (packagesConfigResult is not null)
                {
                    // we might have to merge this dependency with some others
                    if (results.TryGetValue(relativeProjectPath, out var existingProjectDiscovery))
                    {
                        // merge SDK and packages.config results
                        var mergedDependencies = existingProjectDiscovery.Dependencies.Concat(packagesConfigResult.Dependencies)
                            .DistinctBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
                            .OrderBy(d => d.Name)
                            .ToImmutableArray();
                        var mergedTargetFrameworks = existingProjectDiscovery.TargetFrameworks.Concat(packagesConfigResult.TargetFrameworks)
                            .Select(t =>
                            {
                                try
                                {
                                    var tfm = NuGetFramework.Parse(t);
                                    return tfm.GetShortFolderName();
                                }
                                catch
                                {
                                    return string.Empty;
                                }
                            })
                            .Where(tfm => !string.IsNullOrEmpty(tfm))
                            .Distinct()
                            .OrderBy(tfm => tfm)
                            .ToImmutableArray();
                        var mergedProperties = existingProjectDiscovery.Properties; // packages.config discovery doesn't produce properties
                        var mergedImportedFiles = existingProjectDiscovery.ImportedFiles; // packages.config discovery doesn't produce imported files
                        var mergedAdditionalFiles = existingProjectDiscovery.AdditionalFiles.Concat(packagesConfigResult.AdditionalFiles)
                            .Distinct(StringComparer.OrdinalIgnoreCase)
                            .OrderBy(f => f)
                            .ToImmutableArray();
                        var mergedResult = new ProjectDiscoveryResult()
                        {
                            FilePath = existingProjectDiscovery.FilePath,
                            Dependencies = mergedDependencies,
                            TargetFrameworks = mergedTargetFrameworks,
                            Properties = mergedProperties,
                            ImportedFiles = mergedImportedFiles,
                            AdditionalFiles = mergedAdditionalFiles,
                        };
                        results[relativeProjectPath] = mergedResult;
                    }
                    else
                    {
                        // add packages.config results
                        results[relativeProjectPath] = new ProjectDiscoveryResult()
                        {
                            FilePath = relativeProjectPath,
                            Dependencies = packagesConfigResult.Dependencies,
                            TargetFrameworks = packagesConfigResult.TargetFrameworks,
                            ImportedFiles = [], // no imported files resolved for packages.config scenarios
                            AdditionalFiles = packagesConfigResult.AdditionalFiles,
                        };
                    }
                }
            }
        }

        return [.. results.Values];
    }

    internal static async Task WriteResultsAsync(string repoRootPath, string outputPath, WorkspaceDiscoveryResult result)
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
        await File.WriteAllTextAsync(resultPath, resultJson);
    }
}
