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

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.KebabCaseLower,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public RunWorker(IApiHandler apiHandler, ILogger logger)
    {
        _apiHandler = apiHandler;
        _logger = logger;
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

            var allDependencyFiles = new Dictionary<string, DependencyFile>();
            foreach (var directory in job.GetAllDirectories())
            {
                var localPath = PathHelper.JoinPath(repoContentsPath.FullName, directory);
                lastUsedPackageSourceUrls = NuGetContext.GetPackageSourceUrls(localPath);
                var result = await RunForDirectory(job, repoContentsPath, directory, baseCommitSha);
                foreach (var dependencyFile in result.Base64DependencyFiles)
                {
                    allDependencyFiles[dependencyFile.Name] = dependencyFile;
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
            error = new PrivateSourceAuthenticationFailure()
            {
                Details = $"({string.Join("|", lastUsedPackageSourceUrls)})",
            };
        }
        catch (MissingFileException ex)
        {
            error = new DependencyFileNotFound()
            {
                Details = ex.FilePath,
            };
        }
        catch (UpdateNotPossibleException ex)
        {
            error = new UpdateNotPossible()
            {
                Details = ex.Dependencies,
            };
        }
        catch (Exception ex)
        {
            error = new UnknownError()
            {
                Details = ex.ToString(),
            };
        }

        if (error is not null)
        {
            await _apiHandler.RecordUpdateJobError(error);
        }

        await _apiHandler.MarkAsProcessed(new() { BaseCommitSha = baseCommitSha });

        return runResult;
    }

    private async Task<RunResult> RunForDirectory(Job job, DirectoryInfo repoContentsPath, string repoDirectory, string baseCommitSha)
    {
        var discoveryWorker = new DiscoveryWorker(_logger);
        var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, repoDirectory);

        _logger.Log("Discovery JSON content:");
        _logger.Log(JsonSerializer.Serialize(discoveryResult, DiscoveryWorker.SerializerOptions));

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
            foreach (var project in discoveryResult.Projects)
            {
                // TODO: include global.json, etc.
                var path = Path.Join(discoveryResult.Path, project.FilePath).NormalizePathToUnix().EnsurePrefix("/");
                var localPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, project.FilePath);
                var content = await File.ReadAllTextAsync(localPath);
                originalDependencyFileContents[path] = content;
                
                // track packages.config if it exists
                var projectDirectory = Path.GetDirectoryName(project.FilePath);
                var packagesConfigPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, projectDirectory, "packages.config");
                var normalizedPackagesConfigPath = Path.Join(discoveryResult.Path, projectDirectory, "packages.config").NormalizePathToUnix().EnsurePrefix("/");
                if (File.Exists(packagesConfigPath))
                {
                    var packagesConfigContent = await File.ReadAllTextAsync(packagesConfigPath);
                    originalDependencyFileContents[normalizedPackagesConfigPath] = packagesConfigContent;
                }
            }

            // do update
            _logger.Log($"Running update in directory {repoDirectory}");
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

                    var analyzeWorker = new AnalyzeWorker(_logger);
                    var dependencyInfo = new DependencyInfo()
                    {
                        Name = dependency.Name,
                        Version = dependency.Version!,
                        IsVulnerable = false,
                        IgnoredVersions = [],
                        Vulnerabilities = [],
                    };
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    // TODO: log analysisResult
                    if (analysisResult.CanUpdate)
                    {
                        // TODO: this is inefficient, but not likely causing a bottleneck
                        var previousDependency = discoveredUpdatedDependencies.Dependencies
                            .Single(d => d.Name == dependency.Name);
                        var updatedDependency = new ReportedDependency()
                        {
                            Name = dependency.Name,
                            Version = analysisResult.UpdatedVersion,
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    File = dependency.Type == DependencyType.PackagesConfig ? GetPackagesConfigFromCsprojLocation(Path.Join(discoveryResult.Path, project.FilePath).NormalizePathToUnix().EnsurePrefix("/")) : Path.Join(discoveryResult.Path, project.FilePath).NormalizePathToUnix().EnsurePrefix("/"),
                                    Requirement = analysisResult.UpdatedVersion,
                                    Groups = previousDependency.Requirements.Single().Groups,
                                    Source = new RequirementSource()
                                    {
                                        SourceUrl = analysisResult.UpdatedDependencies.Single(d => d.Name == dependency.Name).InfoUrl,
                                    },
                                }
                            ],
                            PreviousVersion = dependency.Version,
                            PreviousRequirements = previousDependency.Requirements,
                        };

                        var updateWorker = new UpdaterWorker(_logger);
                        var dependencyFilePath = Path.Join(discoveryResult.Path, project.FilePath).NormalizePathToUnix();
                        var updateResult = await updateWorker.RunAsync(repoContentsPath.FullName, dependencyFilePath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: false);
                        // TODO: need to report if anything was actually updated
                        if (updateResult.ErrorType is null || updateResult.ErrorType == ErrorType.None)
                        {
                            actualUpdatedDependencies.Add(updatedDependency);
                        }
                    }
                }
            }

            // create PR - we need to manually check file contents; we can't easily use `git status` in tests
            var updatedDependencyFiles = new List<DependencyFile>();
            foreach (var project in discoveryResult.Projects)
            {
                var projectPath = Path.Join(discoveryResult.Path, project.FilePath).NormalizePathToUnix().EnsurePrefix("/");
                var localProjectPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, project.FilePath);
                var updatedProjectContent = await File.ReadAllTextAsync(localProjectPath);
                var originalProjectContent = originalDependencyFileContents[projectPath];

                if (updatedProjectContent != originalProjectContent)
                {
                    updatedDependencyFiles.Add(new DependencyFile()
                    {
                        Name = project.FilePath,
                        Content = updatedProjectContent,
                        Directory = discoveryResult.Path,
                    });
                }

                var projectDirectory = Path.GetDirectoryName(project.FilePath);
                var packagesConfigPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, projectDirectory, "packages.config");
                var normalizedPackagesConfigPath = Path.Join(discoveryResult.Path, projectDirectory, "packages.config").NormalizePathToUnix().EnsurePrefix("/");

                if (File.Exists(packagesConfigPath))
                {
                    var updatedPackagesConfigContent = await File.ReadAllTextAsync(packagesConfigPath);
                    var originalPackagesConfigContent = originalDependencyFileContents[normalizedPackagesConfigPath];

                    if (updatedPackagesConfigContent != originalPackagesConfigContent)
                    {
                        updatedDependencyFiles.Add(new DependencyFile()
                        {
                            Name = Path.Join(projectDirectory!, "packages.config"),
                            Content = updatedPackagesConfigContent,
                            Directory = discoveryResult.Path,
                        });
                    }
                }
            }

            if (updatedDependencyFiles.Count > 0)
            {
                var createPullRequest = new CreatePullRequest()
                {
                    Dependencies = actualUpdatedDependencies.ToArray(),
                    UpdatedDependencyFiles = updatedDependencyFiles.ToArray(),
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
            Base64DependencyFiles = originalDependencyFileContents.Select(kvp => new DependencyFile()
            {
                Name = Path.GetFileName(kvp.Key),
                Content = Convert.ToBase64String(Encoding.UTF8.GetBytes(kvp.Value)),
                Directory = Path.GetDirectoryName(kvp.Key)!.NormalizePathToUnix(),
            }).ToArray(),
            BaseCommitSha = baseCommitSha,
        };
        return result;
    }

    internal static UpdatedDependencyList GetUpdatedDependencyListFromDiscovery(WorkspaceDiscoveryResult discoveryResult, string pathToContents)
    {
        string GetFullRepoPath(string path)
        {
            // ensures `path\to\file` is `/path/to/file`
            return Path.Join(discoveryResult.Path, path).NormalizePathToUnix().NormalizeUnixPathParts().EnsurePrefix("/");
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
        if (discoveryResult.DirectoryPackagesProps is not null)
        {
            auxiliaryFiles.Add(GetFullRepoPath(discoveryResult.DirectoryPackagesProps.FilePath));
        }

        foreach (var project in discoveryResult.Projects)
        {
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            var pathToPackagesConfig = Path.Join(pathToContents, discoveryResult.Path, projectDirectory, "packages.config").NormalizePathToUnix().EnsurePrefix("/");

            if (File.Exists(pathToPackagesConfig))
            {
                auxiliaryFiles.Add(GetFullRepoPath(Path.Join(projectDirectory, "packages.config")));
            }
        }

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
                            File = d.Type == DependencyType.PackagesConfig ? GetPackagesConfigFromCsprojLocation(GetFullRepoPath(p.FilePath)) : GetFullRepoPath(p.FilePath),
                            Requirement = d.Version!,
                            Groups = ["dependencies"],
                        }],
                        Version = d.Version,
                    }
                );
            }).ToArray(),
            DependencyFiles = discoveryResult.Projects.Select(p => GetFullRepoPath(p.FilePath)).Concat(auxiliaryFiles).ToArray(),
        };
        return updatedDependencyList;
    }

    private static string GetPackagesConfigFromCsprojLocation(string fullRepoPath)
    {
        int lastSlash;
        fullRepoPath = Path.GetFullPath(fullRepoPath).NormalizePathToUnix().EnsurePrefix("/");

        lastSlash = fullRepoPath.LastIndexOf('/');
    
        return fullRepoPath.Substring(0, lastSlash + 1) + "packages.config";
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
