using System.Collections.Immutable;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public class RunWorker
{
    private readonly IApiHandler _apiHandler;
    private readonly ILogger _logger;
    private readonly IDiscoveryWorker _discoveryWorker;
    private readonly IAnalyzeWorker _analyzeWorker;
    private readonly IUpdaterWorker _updaterWorker;

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.KebabCaseLower,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(), new RequirementConverter() },
    };

    public RunWorker(IApiHandler apiHandler, IDiscoveryWorker discoverWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updateWorker, ILogger logger)
    {
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
        string[] lastUsedPackageSourceUrls = []; // used for error reporting below
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
                lastUsedPackageSourceUrls = NuGetContext.GetPackageSourceUrls(localPath);
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
        catch (HttpRequestException ex)
        when (ex.StatusCode == HttpStatusCode.Unauthorized || ex.StatusCode == HttpStatusCode.Forbidden)
        {
            error = new PrivateSourceAuthenticationFailure(lastUsedPackageSourceUrls);
        }
        catch (MissingFileException ex)
        {
            error = new DependencyFileNotFound(ex.FilePath);
        }
        catch (UpdateNotPossibleException ex)
        {
            error = new UpdateNotPossible(ex.Dependencies);
        }
        catch (Exception ex)
        {
            error = new UnknownError(ex.ToString());
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

        // report dependencies
        var discoveredUpdatedDependencies = GetUpdatedDependencyListFromDiscovery(discoveryResult, repoContentsPath.FullName);
        await _apiHandler.UpdateDependencyList(discoveredUpdatedDependencies);

        // TODO: pull out relevant dependencies, then check each for updates and track the changes
        // TODO: for each top-level dependency, _or_ specific dependency (if security, use transitive)
        var originalDependencyFileContents = new Dictionary<string, string>();
        var allowedUpdates = job.AllowedUpdates ?? [];
        var actualUpdatedDependencies = new List<ReportedDependency>();
        if (allowedUpdates.Any(a => a.UpdateType == "all"))
        {
            await _apiHandler.IncrementMetric(new()
            {
                Metric = "updater.started",
                Tags = { ["operation"] = "group_update_all_versions" },
            });

            // track original contents for later handling
            async Task TrackOriginalContentsAsync(string directory, string fileName)
            {
                var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
                var localFullPath = Path.Join(repoContentsPath.FullName, repoFullPath);
                var content = await File.ReadAllTextAsync(localFullPath);
                originalDependencyFileContents[repoFullPath] = content;
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
            _logger.Info($"Running update in directory {repoDirectory}");
            foreach (var project in discoveryResult.Projects)
            {
                foreach (var dependency in project.Dependencies.Where(d => !d.IsTransitive))
                {
                    if (dependency.Name == "Microsoft.NET.Sdk")
                    {
                        // this can't be updated
                        // TODO: pull this out of discovery?
                        continue;
                    }

                    if (dependency.Version is null)
                    {
                        // if we don't know the version, there's nothing we can do
                        continue;
                    }

                    var ignoredVersions = GetIgnoredRequirementsForDependency(job, dependency.Name);
                    var dependencyInfo = new DependencyInfo()
                    {
                        Name = dependency.Name,
                        Version = dependency.Version!,
                        IsVulnerable = false,
                        IgnoredVersions = ignoredVersions,
                        Vulnerabilities = [],
                    };
                    var analysisResult = await _analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    // TODO: log analysisResult
                    if (analysisResult.CanUpdate)
                    {
                        var dependencyLocation = Path.Join(discoveryResult.Path, project.FilePath).FullyNormalizedRootedPath();

                        // TODO: this is inefficient, but not likely causing a bottleneck
                        var previousDependency = discoveredUpdatedDependencies.Dependencies
                            .Single(d => d.Name == dependency.Name && d.Requirements.Single().File == dependencyLocation);
                        var updatedDependency = new ReportedDependency()
                        {
                            Name = dependency.Name,
                            Version = analysisResult.UpdatedVersion,
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    File = dependencyLocation,
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

                        var dependencyFilePath = Path.Join(discoveryResult.Path, project.FilePath).FullyNormalizedRootedPath();
                        var updateResult = await _updaterWorker.RunAsync(repoContentsPath.FullName, dependencyFilePath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: false);
                        // TODO: need to report if anything was actually updated
                        if (updateResult.ErrorType is null || updateResult.ErrorType == ErrorType.None)
                        {
                            if (dependencyLocation != dependencyFilePath)
                            {
                                updatedDependency.Requirements.All(r => r.File == dependencyFilePath);
                            }

                            actualUpdatedDependencies.Add(updatedDependency);
                        }
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
        }
        else
        {
            // TODO: throw if no updates performed
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
        var updatedDependencyList = new UpdatedDependencyList()
        {
            Dependencies = discoveryResult.Projects.SelectMany(p =>
            {
                return p.Dependencies.Where(d => d.Version is not null).Select(d =>
                    new ReportedDependency()
                    {
                        Name = d.Name,
                        Requirements = d.IsTransitive ? [] : [new ReportedRequirement()
                        {
                            File = GetFullRepoPath(p.FilePath),
                            Requirement = d.Version!,
                            Groups = ["dependencies"],
                        }],
                        Version = d.Version,
                    }
                );
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
