using System.Collections.Immutable;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

using Microsoft.Extensions.FileSystemGlobbing;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Utilities;

using static NuGetUpdater.Core.Utilities.EOLHandling;

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
        Converters = { new JsonStringEnumConverter(), new RequirementConverter(), new VersionConverter() },
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

    public async Task RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath, string baseCommitSha, FileInfo outputFilePath)
    {
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath.FullName);
        var jobWrapper = Deserialize(jobFileContent);
        var result = await RunAsync(jobWrapper.Job, repoContentsPath, baseCommitSha);
        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        await File.WriteAllTextAsync(outputFilePath.FullName, resultJson);
    }

    public Task<RunResult> RunAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha)
    {
        return RunWithErrorHandlingAsync(job, repoContentsPath, baseCommitSha);
    }

    private async Task<RunResult> RunWithErrorHandlingAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha)
    {
        JobErrorBase? error = null;
        var currentDirectory = repoContentsPath.FullName; // used for error reporting below
        var runResult = new RunResult()
        {
            Base64DependencyFiles = [],
            BaseCommitSha = baseCommitSha,
        };

        try
        {
            MSBuildHelper.RegisterMSBuild(repoContentsPath.FullName, repoContentsPath.FullName);

            var experimentsManager = ExperimentsManager.GetExperimentsManager(job.Experiments);
            var allDependencyFiles = new Dictionary<string, DependencyFile>();
            foreach (var directory in job.GetAllDirectories())
            {
                var localPath = PathHelper.JoinPath(repoContentsPath.FullName, directory);
                currentDirectory = localPath;
                var result = await RunForDirectory(job, repoContentsPath, directory, baseCommitSha, experimentsManager);
                foreach (var dependencyFile in result.Base64DependencyFiles)
                {
                    var uniqueKey = Path.GetFullPath(Path.Join(dependencyFile.Directory, dependencyFile.Name)).NormalizePathToUnix().EnsurePrefix("/");
                    allDependencyFiles[uniqueKey] = dependencyFile;
                }
            }

            runResult = new RunResult()
            {
                Base64DependencyFiles = allDependencyFiles.Values.ToArray(),
                BaseCommitSha = baseCommitSha,
            };
        }
        catch (Exception ex)
        {
            error = JobErrorBase.ErrorFromException(ex, _jobId, currentDirectory);
        }

        if (error is not null)
        {
            await _apiHandler.RecordUpdateJobError(error);
        }

        await _apiHandler.MarkAsProcessed(new(baseCommitSha));

        return runResult;
    }

    private async Task<RunResult> RunForDirectory(Job job, DirectoryInfo repoContentsPath, string repoDirectory, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        var discoveryResult = await _discoveryWorker.RunAsync(repoContentsPath.FullName, repoDirectory);

        _logger.Info("Discovery JSON content:");
        _logger.Info(JsonSerializer.Serialize(discoveryResult, DiscoveryWorker.SerializerOptions));

        // TODO: report errors

        // report dependencies
        var discoveredUpdatedDependencies = GetUpdatedDependencyListFromDiscovery(discoveryResult, repoContentsPath.FullName);
        await _apiHandler.UpdateDependencyList(discoveredUpdatedDependencies);

        var incrementMetric = GetIncrementMetric(job);
        await _apiHandler.IncrementMetric(incrementMetric);

        // TODO: pull out relevant dependencies, then check each for updates and track the changes
        var originalDependencyFileContents = new Dictionary<string, string>();
        var originalDependencyFileEOFs = new Dictionary<string, EOLType>();
        var actualUpdatedDependencies = new List<ReportedDependency>();

        // track original contents for later handling
        async Task TrackOriginalContentsAsync(string directory, string fileName)
        {
            var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
            var localFullPath = Path.Join(repoContentsPath.FullName, repoFullPath);
            var content = await File.ReadAllTextAsync(localFullPath);
            originalDependencyFileContents[repoFullPath] = content;
            originalDependencyFileEOFs[repoFullPath] = content.GetPredominantEOL();
        }

        foreach (var project in discoveryResult.Projects)
        {
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            await TrackOriginalContentsAsync(discoveryResult.Path, project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
                await TrackOriginalContentsAsync(discoveryResult.Path, extraFilePath);
            }
            // TODO: include global.json, etc.
        }

        // do update
        var updateOperations = GetUpdateOperations(discoveryResult).ToArray();
        var allowedUpdateOperations = updateOperations.Where(u => IsUpdateAllowed(job, u.Dependency)).ToArray();

        // requested update isn't listed => SecurityUpdateNotNeeded
        var expectedSecurityUpdateDependencyNames = job.SecurityAdvisories
            .Select(s => s.DependencyName)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var actualUpdateDependencyNames = allowedUpdateOperations
            .Select(u => u.Dependency.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var expectedDependencyUpdateMissingInActual = expectedSecurityUpdateDependencyNames
            .Except(actualUpdateDependencyNames, StringComparer.OrdinalIgnoreCase)
            .OrderBy(d => d, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        foreach (var missingSecurityUpdate in expectedDependencyUpdateMissingInActual)
        {
            await _apiHandler.RecordUpdateJobError(new SecurityUpdateNotNeeded(missingSecurityUpdate));
        }

        foreach (var updateOperation in allowedUpdateOperations)
        {
            var dependency = updateOperation.Dependency;
            _logger.Info($"Updating [{dependency.Name}] in [{updateOperation.ProjectPath}]");

            var dependencyInfo = GetDependencyInfo(job, dependency);
            var analysisResult = await _analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
            // TODO: log analysisResult
            if (analysisResult.CanUpdate)
            {
                // TODO: this is inefficient, but not likely causing a bottleneck
                var previousDependency = discoveredUpdatedDependencies.Dependencies
                    .Single(d => d.Name == dependency.Name && d.Requirements.Single().File == updateOperation.ProjectPath);
                var updatedDependency = new ReportedDependency()
                {
                    Name = dependency.Name,
                    Version = analysisResult.UpdatedVersion,
                    Requirements =
                    [
                        new ReportedRequirement()
                        {
                            File = updateOperation.ProjectPath,
                            Requirement = analysisResult.UpdatedVersion,
                            Groups = previousDependency.Requirements.Single().Groups,
                            Source = new RequirementSource()
                            {
                                SourceUrl = analysisResult.UpdatedDependencies.FirstOrDefault(d => d.Name == dependency.Name)?.InfoUrl,
                            },
                        }
                    ],
                    PreviousVersion = dependency.Version,
                    PreviousRequirements = previousDependency.Requirements,
                };

                var updateResult = await _updaterWorker.RunAsync(repoContentsPath.FullName, updateOperation.ProjectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: dependency.IsTransitive);
                // TODO: need to report if anything was actually updated
                if (updateResult.Error is null)
                {
                    actualUpdatedDependencies.Add(updatedDependency);
                }
            }
        }

        // create PR - we need to manually check file contents; we can't easily use `git status` in tests
        var updatedDependencyFiles = new Dictionary<string, DependencyFile>();
        async Task AddUpdatedFileIfDifferentAsync(string directory, string fileName)
        {
            var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
            var localFullPath = Path.GetFullPath(Path.Join(repoContentsPath.FullName, repoFullPath));
            var originalContent = originalDependencyFileContents[repoFullPath];
            var updatedContent = await File.ReadAllTextAsync(localFullPath);

            updatedContent = updatedContent.SetEOL(originalDependencyFileEOFs[repoFullPath]);
            await File.WriteAllTextAsync(localFullPath, updatedContent);

            if (updatedContent != originalContent)
            {

                updatedDependencyFiles[localFullPath] = new DependencyFile()
                {
                    Name = Path.GetFileName(repoFullPath),
                    Directory = Path.GetDirectoryName(repoFullPath)!.NormalizePathToUnix(),
                    Content = updatedContent,
                };
            }
        }

        foreach (var project in discoveryResult.Projects)
        {
            await AddUpdatedFileIfDifferentAsync(discoveryResult.Path, project.FilePath);
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
                await AddUpdatedFileIfDifferentAsync(discoveryResult.Path, extraFilePath);
            }
            // TODO: handle global.json, etc.
        }

        if (updatedDependencyFiles.Count > 0)
        {
            var updatedDependencyFileList = updatedDependencyFiles
                .OrderBy(kvp => kvp.Key)
                .Select(kvp => kvp.Value)
                .ToArray();
            var createPullRequest = new CreatePullRequest()
            {
                Dependencies = actualUpdatedDependencies.ToArray(),
                UpdatedDependencyFiles = updatedDependencyFileList,
                BaseCommitSha = baseCommitSha,
                CommitMessage = "TODO: message",
                PrTitle = "TODO: title",
                PrBody = "TODO: body",
            };
            await _apiHandler.CreatePullRequest(createPullRequest);
            // TODO: log updated dependencies to console
        }
        else
        {
            // TODO: log or throw if nothing was updated, but was expected to be
        }

        var result = new RunResult()
        {
            Base64DependencyFiles = originalDependencyFileContents.OrderBy(kvp => kvp.Key).Select(kvp =>
            {
                var fullPath = kvp.Key.FullyNormalizedRootedPath();
                return new DependencyFile()
                {
                    Name = Path.GetFileName(fullPath),
                    Content = Convert.ToBase64String(Encoding.UTF8.GetBytes(kvp.Value)),
                    Directory = Path.GetDirectoryName(fullPath)!.NormalizePathToUnix(),
                };
            }).ToArray(),
            BaseCommitSha = baseCommitSha,
        };
        return result;
    }

    internal static IEnumerable<(string ProjectPath, Dependency Dependency)> GetUpdateOperations(WorkspaceDiscoveryResult discovery)
    {
        // discovery is grouped by project then dependency, but we want to pivot and return a list of update operations sorted by dependency name then project path

        var updateOrder = new Dictionary<string, Dictionary<string, Dictionary<string, Dependency>>>(StringComparer.OrdinalIgnoreCase);
        //                     <dependency name,     <project path, specific dependencies>>

        // collect
        foreach (var project in discovery.Projects)
        {
            var projectPath = Path.Join(discovery.Path, project.FilePath).FullyNormalizedRootedPath();
            foreach (var dependency in project.Dependencies)
            {
                var dependencyGroup = updateOrder.GetOrAdd(dependency.Name, () => new Dictionary<string, Dictionary<string, Dependency>>(PathComparer.Instance));
                var dependenciesForProject = dependencyGroup.GetOrAdd(projectPath, () => new Dictionary<string, Dependency>(StringComparer.OrdinalIgnoreCase));
                dependenciesForProject[dependency.Name] = dependency;
            }
        }

        // return
        foreach (var dependencyName in updateOrder.Keys.OrderBy(k => k, StringComparer.OrdinalIgnoreCase))
        {
            var projectDependencies = updateOrder[dependencyName];
            foreach (var projectPath in projectDependencies.Keys.OrderBy(p => p, PathComparer.Instance))
            {
                var dependencies = projectDependencies[projectPath];
                var dependency = dependencies[dependencyName];
                yield return (projectPath, dependency);
            }
        }
    }

    internal static IncrementMetric GetIncrementMetric(Job job)
    {
        var isSecurityUpdate = job.AllowedUpdates.Any(a => a.UpdateType == UpdateType.Security) || job.SecurityUpdatesOnly;
        var metricOperation = isSecurityUpdate ?
            (job.UpdatingAPullRequest ? "update_security_pr" : "create_security_pr")
            : (job.UpdatingAPullRequest ? "update_version_pr" : "group_update_all_versions");
        var increment = new IncrementMetric()
        {
            Metric = "updater.started",
            Tags = { ["operation"] = metricOperation },
        };
        return increment;
    }

    internal static bool IsUpdateAllowed(Job job, Dependency dependency)
    {
        if (dependency.Name.Equals("Microsoft.NET.Sdk", StringComparison.OrdinalIgnoreCase))
        {
            // this can't be updated
            // TODO: pull this out of discovery?
            return false;
        }

        if (dependency.Version is null)
        {
            // if we don't know the version, there's nothing we can do
            // TODO: pull this out of discovery?
            return false;
        }

        var version = NuGetVersion.Parse(dependency.Version);
        var dependencyInfo = GetDependencyInfo(job, dependency);
        var isVulnerable = dependencyInfo.Vulnerabilities.Any(v => v.IsVulnerable(version));
        var allowed = job.AllowedUpdates.Any(allowedUpdate =>
        {
            // check name restriction, if any
            if (allowedUpdate.DependencyName is not null)
            {
                var matcher = new Matcher(StringComparison.OrdinalIgnoreCase)
                    .AddInclude(allowedUpdate.DependencyName);
                var result = matcher.Match(dependency.Name);
                if (!result.HasMatches)
                {
                    return false;
                }
            }

            var isSecurityUpdate = allowedUpdate.UpdateType == UpdateType.Security || job.SecurityUpdatesOnly;
            if (isSecurityUpdate)
            {
                // only update if it's vulnerable
                return isVulnerable;
            }
            else
            {
                // not a security update, so only update if...
                // ...we've been explicitly asked to update this
                if ((job.Dependencies ?? []).Any(d => d.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }

                // ...no specific update being performed, do it if it's not transitive
                return !dependency.IsTransitive;
            }
        });

        return allowed;
    }

    internal static ImmutableArray<Requirement> GetIgnoredRequirementsForDependency(Job job, string dependencyName)
    {
        var ignoreConditions = job.IgnoreConditions
            .Where(c => c.DependencyName.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (ignoreConditions.Length == 1 && ignoreConditions[0].VersionRequirement is null)
        {
            // if only one match with no version requirement, ignore all versions
            return [Requirement.Parse("> 0.0.0")];
        }

        var ignoredVersions = ignoreConditions
            .Select(c => c.VersionRequirement)
            .Where(r => r is not null)
            .Cast<Requirement>()
            .ToImmutableArray();
        return ignoredVersions;
    }

    internal static DependencyInfo GetDependencyInfo(Job job, Dependency dependency)
    {
        var dependencyVersion = NuGetVersion.Parse(dependency.Version!);
        var securityAdvisories = job.SecurityAdvisories.Where(s => s.DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)).ToArray();
        var isVulnerable = securityAdvisories.Any(s => (s.AffectedVersions ?? []).Any(v => v.IsSatisfiedBy(dependencyVersion)));
        var ignoredVersions = GetIgnoredRequirementsForDependency(job, dependency.Name);
        var vulnerabilities = securityAdvisories.Select(s => new SecurityVulnerability()
        {
            DependencyName = dependency.Name,
            PackageManager = "nuget",
            VulnerableVersions = s.AffectedVersions ?? [],
            SafeVersions = s.SafeVersions.ToImmutableArray(),
        }).ToImmutableArray();
        var dependencyInfo = new DependencyInfo()
        {
            Name = dependency.Name,
            Version = dependencyVersion.ToString(),
            IsVulnerable = isVulnerable,
            IgnoredVersions = ignoredVersions,
            Vulnerabilities = vulnerabilities,
        };
        return dependencyInfo;
    }

    internal static UpdatedDependencyList GetUpdatedDependencyListFromDiscovery(WorkspaceDiscoveryResult discoveryResult, string pathToContents)
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

        var dependencyFiles = discoveryResult.Projects
            .Select(p => GetFullRepoPath(p.FilePath))
            .Concat(auxiliaryFiles)
            .Distinct()
            .OrderBy(p => p)
            .ToArray();
        var orderedProjects = discoveryResult.Projects
            .OrderBy(p => Path.Join(discoveryResult.Path, p.FilePath).FullyNormalizedRootedPath(), PathComparer.Instance)
            .ToArray();
        var updatedDependencyList = new UpdatedDependencyList()
        {
            Dependencies = orderedProjects.SelectMany(p =>
            {
                return p.Dependencies
                    .Where(d => d.Version is not null)
                    .OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
                    .Select(d =>
                        new ReportedDependency()
                        {
                            Name = d.Name,
                            Requirements = [new ReportedRequirement()
                            {
                                File = GetFullRepoPath(p.FilePath),
                                Requirement = d.Version!,
                                Groups = ["dependencies"],
                            }],
                            Version = d.Version,
                        });
            }).ToArray(),
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
