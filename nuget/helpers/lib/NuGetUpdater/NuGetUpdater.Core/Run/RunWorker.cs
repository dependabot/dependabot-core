using System.Collections.Immutable;
using System.IO.Enumeration;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Run;

public class RunWorker
{
    private readonly string _jobId;
    private readonly IApiHandler _apiHandler;
    private readonly ILogger _logger;
    private readonly IDiscoveryWorker _discoveryWorker;
    private readonly IAnalyzeWorker _analyzeWorker;
    private readonly IUpdaterWorker _updaterWorker;

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.KebabCaseLower,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(), new PullRequestConverter(), new RequirementConverter(), new VersionConverter() },
    };

    public RunWorker(string jobId, IApiHandler apiHandler, IDiscoveryWorker discoverWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updateWorker, ILogger logger)
    {
        _jobId = jobId;
        _apiHandler = apiHandler;
        _logger = logger;
        _discoveryWorker = discoverWorker;
        _analyzeWorker = analyzeWorker;
        _updaterWorker = updateWorker;
    }

    public async Task RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, FileInfo outputFilePath)
    {
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath.FullName);
        var jobWrapper = Deserialize(jobFileContent);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        await RunAsync(jobWrapper.Job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, experimentsManager);
    }

    public async Task RunAsync(Job job, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        await RunScenarioHandlersWithErrorHandlingAsync(job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, experimentsManager);
    }

    private static readonly ImmutableArray<IUpdateHandler> UpdateHandlers =
    [
        GroupUpdateAllVersionsHandler.Instance,
        RefreshGroupUpdatePullRequestHandler.Instance,
        CreateSecurityUpdatePullRequestHandler.Instance,
        RefreshSecurityUpdatePullRequestHandler.Instance,
        RefreshVersionUpdatePullRequestHandler.Instance,
    ];

    public static IUpdateHandler GetUpdateHandler(Job job) =>
        UpdateHandlers.FirstOrDefault(h => h.CanHandle(job)) ?? throw new InvalidOperationException("Unable to find appropriate update handler.");

    private async Task RunScenarioHandlersWithErrorHandlingAsync(Job job, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        JobErrorBase? error = null;

        try
        {
            var handler = GetUpdateHandler(job);
            _logger.Info($"Starting update job of type {handler.TagName}");
            await handler.HandleAsync(job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, _discoveryWorker, _analyzeWorker, _updaterWorker, _apiHandler, experimentsManager, _logger);
        }
        catch (Exception ex)
        {
            error = JobErrorBase.ErrorFromException(ex, _jobId, repoContentsPath.FullName);
        }

        if (error is not null)
        {
            await _apiHandler.RecordUpdateJobError(error, _logger);
        }

        await _apiHandler.MarkAsProcessed(new(baseCommitSha));
    }

    internal static ImmutableArray<UpdateOperationBase> PatchInOldVersions(ImmutableArray<UpdateOperationBase> updateOperations, ProjectDiscoveryResult? projectDiscovery)
    {
        if (projectDiscovery is null)
        {
            return updateOperations;
        }

        var originalPackageVersions = projectDiscovery
            .Dependencies
            .ToDictionary(d => d.Name, d => d.Version is null ? null : NuGetVersion.Parse(d.Version), StringComparer.OrdinalIgnoreCase);
        var patchedUpdateOperations = updateOperations
            .Select(uo => uo with { OldVersion = originalPackageVersions.GetValueOrDefault(uo.DependencyName) })
            .ToImmutableArray();
        return patchedUpdateOperations;
    }

    internal static IEnumerable<(string ProjectPath, Dependency Dependency)> GetUpdateOperations(WorkspaceDiscoveryResult discovery)
    {
        // discovery is grouped by project/file then dependency, but we want to pivot and return a list of update operations sorted by dependency name then file path

        var updateOrder = new Dictionary<string, Dictionary<string, Dictionary<string, Dependency>>>(StringComparer.OrdinalIgnoreCase);
        //                     <dependency name,        <file path, specific dependencies>>

        // collect
        void CollectDependenciesForFile(string filePath, IEnumerable<Dependency> dependencies)
        {
            foreach (var dependency in dependencies)
            {
                var dependencyGroup = updateOrder.GetOrAdd(dependency.Name, () => new Dictionary<string, Dictionary<string, Dependency>>(PathComparer.Instance));
                var dependenciesForFile = dependencyGroup.GetOrAdd(filePath, () => new Dictionary<string, Dependency>(StringComparer.OrdinalIgnoreCase));
                dependenciesForFile[dependency.Name] = dependency;
            }
        }
        foreach (var project in discovery.Projects)
        {
            var projectPath = Path.Join(discovery.Path, project.FilePath).FullyNormalizedRootedPath();
            CollectDependenciesForFile(projectPath, project.Dependencies);
        }

        if (discovery.GlobalJson is not null)
        {
            var globalJsonPath = Path.Join(discovery.Path, discovery.GlobalJson.FilePath).FullyNormalizedRootedPath();
            CollectDependenciesForFile(globalJsonPath, discovery.GlobalJson.Dependencies);
        }

        if (discovery.DotNetToolsJson is not null)
        {
            var dotnetToolsJsonPath = Path.Join(discovery.Path, discovery.DotNetToolsJson.FilePath).FullyNormalizedRootedPath();
            CollectDependenciesForFile(dotnetToolsJsonPath, discovery.DotNetToolsJson.Dependencies);
        }

        // return
        foreach (var dependencyName in updateOrder.Keys.OrderBy(k => k, StringComparer.OrdinalIgnoreCase))
        {
            var fileDependencies = updateOrder[dependencyName];
            foreach (var filePath in fileDependencies.Keys.OrderBy(p => p, PathComparer.Instance))
            {
                var dependencies = fileDependencies[filePath];
                var dependency = dependencies[dependencyName];
                yield return (filePath, dependency);
            }
        }
    }

    internal static DependencyInfo GetDependencyInfo(Job job, Dependency dependency)
    {
        var dependencyVersion = NuGetVersion.Parse(dependency.Version!);
        var securityAdvisories = job.SecurityAdvisories.Where(s => s.DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)).ToArray();
        var isVulnerable = securityAdvisories.Any(s => (s.AffectedVersions ?? []).Any(v => v.IsSatisfiedBy(dependencyVersion)));
        var ignoredVersions = job.IgnoreConditions
            .Where(c => FileSystemName.MatchesSimpleExpression(c.DependencyName, dependency.Name))
            .Select(c => c.VersionRequirement)
            .Where(r => r is not null)
            .Cast<Requirement>()
            .ToImmutableArray();
        var vulnerabilities = securityAdvisories.Select(s => new SecurityVulnerability()
        {
            DependencyName = dependency.Name,
            PackageManager = "nuget",
            VulnerableVersions = s.AffectedVersions ?? [],
            SafeVersions = s.SafeVersions.ToImmutableArray(),
        }).ToImmutableArray();
        var ignoredUpdateTypes = job.IgnoreConditions
            .Where(c => FileSystemName.MatchesSimpleExpression(c.DependencyName, dependency.Name))
            .SelectMany(c => c.UpdateTypes ?? [])
            .Distinct()
            .ToImmutableArray();
        var dependencyInfo = new DependencyInfo()
        {
            Name = dependency.Name,
            Version = dependencyVersion.ToString(),
            IsVulnerable = isVulnerable,
            IgnoredVersions = ignoredVersions,
            Vulnerabilities = vulnerabilities,
            IgnoredUpdateTypes = ignoredUpdateTypes,
        };
        return dependencyInfo;
    }

    internal static string EnsureCorrectFileCasing(string repoRelativePath, string repoRoot, ILogger logger)
    {
        var fullPath = Path.Join(repoRoot, repoRelativePath);
        var resolvedNames = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(fullPath, repoRoot);
        if (resolvedNames is null)
        {
            logger.Info($"Unable to resolve correct case for file [{repoRelativePath}]; returning original.");
            return repoRelativePath;
        }

        if (resolvedNames.Count != 1)
        {
            logger.Info($"Expected exactly 1 normalized file path for [{repoRelativePath}], instead found {resolvedNames.Count}: {string.Join(", ", resolvedNames)}");
            return repoRelativePath;
        }

        var resolvedName = resolvedNames[0];
        var relativeResolvedName = Path.GetRelativePath(repoRoot, resolvedName).FullyNormalizedRootedPath();
        return relativeResolvedName;
    }

    internal static UpdatedDependencyList GetUpdatedDependencyListFromDiscovery(WorkspaceDiscoveryResult discoveryResult, string repoRoot, ILogger logger)
    {
        string GetFullRepoPath(string path)
        {
            // ensures `path\to\file` is `/path/to/file`
            return Path.Join(discoveryResult.Path, path).FullyNormalizedRootedPath();
        }

        var auxiliaryFiles = new List<string>();
        if (discoveryResult.GlobalJson is not null)
        {
            auxiliaryFiles.Add(GetFullRepoPath(discoveryResult.GlobalJson.FilePath));
        }
        if (discoveryResult.DotNetToolsJson is not null)
        {
            auxiliaryFiles.Add(GetFullRepoPath(discoveryResult.DotNetToolsJson.FilePath));
        }

        foreach (var project in discoveryResult.Projects)
        {
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFileFullPath = Path.Join(projectDirectory, extraFile);
                var extraFileRepoPath = GetFullRepoPath(extraFileFullPath);
                auxiliaryFiles.Add(extraFileRepoPath);
            }
        }

        var allDependenciesWithFilePath = discoveryResult.Projects.SelectMany(p =>
        {
            return p.Dependencies
                .Where(d => d.Version is not null)
                .Select(d =>
                    (p.FilePath, new ReportedDependency()
                    {
                        Name = d.Name,
                        Requirements = [new ReportedRequirement()
                            {
                                File = GetFullRepoPath(p.FilePath),
                                Requirement = d.Version!,
                                Groups = ["dependencies"],
                            }],
                        Version = d.Version,
                    }));
        }).ToList();

        var nonProjectDependencySet = new (string?, IEnumerable<Dependency>)[]
        {
            (discoveryResult.GlobalJson?.FilePath, discoveryResult.GlobalJson?.Dependencies ?? []),
            (discoveryResult.DotNetToolsJson?.FilePath, discoveryResult.DotNetToolsJson?.Dependencies ?? []),
        };

        foreach (var (filePath, dependencies) in nonProjectDependencySet)
        {
            if (filePath is null)
            {
                continue;
            }

            allDependenciesWithFilePath.AddRange(dependencies
                .Where(d => d.Version is not null)
                .Select(d =>
                    (filePath, new ReportedDependency()
                    {
                        Name = d.Name,
                        Requirements = [new ReportedRequirement()
                            {
                                File = GetFullRepoPath(filePath),
                                Requirement = d.Version!,
                                Groups = ["dependencies"],
                            }],
                        Version = d.Version,
                    })));
        }

        var sortedDependencies = allDependenciesWithFilePath
            .OrderBy(pair => Path.Join(discoveryResult.Path, pair.FilePath).FullyNormalizedRootedPath(), PathComparer.Instance)
            .ThenBy(pair => pair.Item2.Name, StringComparer.OrdinalIgnoreCase)
            .Select(pair => pair.Item2)
            .ToArray();

        var dependencyFiles = discoveryResult.Projects
            .Select(p => GetFullRepoPath(p.FilePath))
            .Concat(auxiliaryFiles)
            .Select(p => EnsureCorrectFileCasing(p, repoRoot, logger))
            .Distinct()
            .OrderBy(p => p)
            .ToArray();

        var updatedDependencyList = new UpdatedDependencyList()
        {
            Dependencies = sortedDependencies,
            DependencyFiles = dependencyFiles,
        };
        return updatedDependencyList;
    }

    public static JobFile Deserialize(string json)
    {
        var jobFile = JsonSerializer.Deserialize<JobFile>(json, SerializerOptions);
        if (jobFile is null)
        {
            throw new InvalidOperationException("Unable to deserialize job wrapper.");
        }

        if (jobFile.Job.PackageManager != "nuget")
        {
            throw new InvalidOperationException("Package manager must be 'nuget'");
        }

        return jobFile;
    }
}
