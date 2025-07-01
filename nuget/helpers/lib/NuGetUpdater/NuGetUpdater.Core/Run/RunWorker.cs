using System.Collections.Immutable;
using System.IO;
using System.IO.Enumeration;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

using Microsoft.Extensions.FileSystemGlobbing;

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
        var result = await RunAsync(jobWrapper.Job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, experimentsManager);
        if (experimentsManager.UseLegacyUpdateHandler)
        {
            // only the legacy handler writes this file
            var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
            await File.WriteAllTextAsync(outputFilePath.FullName, resultJson);
        }
    }

    public async Task<RunResult> RunAsync(Job job, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        RunResult result;
        if (experimentsManager.UseLegacyUpdateHandler)
        {
            result = await RunWithErrorHandlingAsync(job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, experimentsManager);
        }
        else
        {
            await RunScenarioHandlersWithErrorHandlingAsync(job, repoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, experimentsManager);

            // the group updater doesn't return this, so we provide an empty object
            result = new RunResult()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = baseCommitSha,
            };
        }

        return result;
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
            await _apiHandler.RecordUpdateJobError(error);
        }

        await _apiHandler.MarkAsProcessed(new(baseCommitSha));
    }

    private async Task<RunResult> RunWithErrorHandlingAsync(Job job, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, ExperimentsManager experimentsManager)
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
            MSBuildHelper.RegisterMSBuild(repoContentsPath.FullName, repoContentsPath.FullName, _logger);

            var allDependencyFiles = new Dictionary<string, DependencyFile>();
            foreach (var directory in job.GetAllDirectories())
            {
                var localPath = PathHelper.JoinPath(repoContentsPath.FullName, directory);
                currentDirectory = localPath;
                var result = await RunForDirectory(job, repoContentsPath, caseInsensitiveRepoContentsPath, directory, baseCommitSha, experimentsManager);
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

    private async Task<RunResult> RunForDirectory(Job job, DirectoryInfo originalRepoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string repoDirectory, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        var repoContentsPath = caseInsensitiveRepoContentsPath ?? originalRepoContentsPath;
        var discoveryResult = await _discoveryWorker.RunAsync(repoContentsPath.FullName, repoDirectory);
        _logger.ReportDiscovery(discoveryResult);

        if (discoveryResult.Error is not null)
        {
            // this is unrecoverable
            await _apiHandler.RecordUpdateJobError(discoveryResult.Error);
            return new()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = baseCommitSha,
            };
        }

        // report dependencies
        var discoveredUpdatedDependencies = GetUpdatedDependencyListFromDiscovery(discoveryResult, originalRepoContentsPath.FullName, _logger);
        await _apiHandler.UpdateDependencyList(discoveredUpdatedDependencies);

        var incrementMetric = GetIncrementMetric(job);
        await _apiHandler.IncrementMetric(incrementMetric);

        // TODO: pull out relevant dependencies, then check each for updates and track the changes
        var actualUpdatedDependencies = new List<ReportedDependency>();

        // track original contents for later handling
        var tracker = new ModifiedFilesTracker(originalRepoContentsPath, _logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // do update
        var updateOperationsPerformed = new List<UpdateOperationBase>();
        var existingPullRequests = job.GetAllExistingPullRequests();
        var unhandledPullRequestDependenciesSet = existingPullRequests
            .Select(pr => pr.Item2.Select(d => d.DependencyName).ToHashSet(StringComparer.OrdinalIgnoreCase))
            .ToHashSet();
        var remainingSecurityIssues = job.SecurityAdvisories
            .Select(s => s.DependencyName)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var updateOperations = GetUpdateOperations(discoveryResult).ToArray();

        foreach (var updateOperation in updateOperations)
        {
            var dependency = updateOperation.Dependency;
            var (isAllowed, message) = UpdatePermittedAndMessage(job, updateOperation.Dependency);
            if (message is SecurityUpdateNotNeeded sec)
            {
                // flag this update operation as having been handled
                remainingSecurityIssues.RemoveWhere(r => r.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase));

                // we only want to send this message if we're in the only update operation for this dependency, otherwise it's ambiguous
                var updateOperationsWithSameName = updateOperations.Where(u => u.Dependency.Name.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase))
                    .ToArray();
                if (updateOperationsWithSameName.Length > 1)
                {
                    // suppress the message
                    message = null;
                }
            }

            await SendApiMessage(message);
            if (!isAllowed)
            {
                continue;
            }

            _logger.Info($"Updating [{dependency.Name}] in [{updateOperation.ProjectPath}]");

            var dependencyInfo = GetDependencyInfo(job, dependency);
            var analysisResult = await _analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
            _logger.ReportAnalysis(analysisResult);

            if (analysisResult.Error is not null)
            {
                await _apiHandler.RecordUpdateJobError(analysisResult.Error);
                continue;
            }

            if (analysisResult.CanUpdate)
            {
                if (!job.UpdatingAPullRequest)
                {
                    var updatedDependencyFromAnalysis = analysisResult.UpdatedDependencies
                        .FirstOrDefault(d => d.Name.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase));
                    if (updatedDependencyFromAnalysis is not null)
                    {
                        var existingPullRequest = job.GetExistingPullRequestForDependencies([updatedDependencyFromAnalysis], considerVersions: true);
                        if (existingPullRequest is not null)
                        {
                            await SendApiMessage(new PullRequestExistsForLatestVersion(dependency.Name, analysisResult.UpdatedVersion));
                            unhandledPullRequestDependenciesSet.RemoveWhere(handled => handled.Count == 1 && handled.Contains(dependency.Name));
                            continue;
                        }
                    }
                }

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

                var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(updateOperation.ProjectPath);
                var updateResult = await _updaterWorker.RunAsync(repoContentsPath.FullName, updateOperation.ProjectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: dependency.IsTransitive);
                if (updateResult.Error is not null)
                {
                    await _apiHandler.RecordUpdateJobError(updateResult.Error);
                }
                else
                {
                    actualUpdatedDependencies.Add(updatedDependency);
                }

                var patchedUpdateOperations = PatchInOldVersions(updateResult.UpdateOperations, projectDiscovery);
                updateOperationsPerformed.AddRange(patchedUpdateOperations);
            }
        }

        // create PR - we need to manually check file contents; we can't easily use `git status` in tests
        var updatedDependencyFiles = await tracker.StopTrackingAsync();
        var normalizedUpdateOperationsPerformed = UpdateOperationBase.NormalizeUpdateOperationCollection(repoContentsPath.FullName, updateOperationsPerformed);
        var report = UpdateOperationBase.GenerateUpdateOperationReport(normalizedUpdateOperationsPerformed);
        _logger.Info(report);

        var sortedUpdatedDependencies = actualUpdatedDependencies.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase).ToArray();
        var resultMessage = GetPullRequestApiMessage(job, [.. updatedDependencyFiles], sortedUpdatedDependencies, normalizedUpdateOperationsPerformed, baseCommitSha);
        switch (resultMessage)
        {
            case ClosePullRequest close:
                var closePrDependencies = close.DependencyNames.ToHashSet(StringComparer.OrdinalIgnoreCase);
                remainingSecurityIssues.RemoveWhere(closePrDependencies.Contains);
                if (!unhandledPullRequestDependenciesSet.Remove(closePrDependencies))
                {
                    // this PR was handled earlier, we don't want to now close it; suppress the message
                    resultMessage = null;
                }
                break;
            case CreatePullRequest create:
                var createPrDependencies = create.Dependencies.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
                remainingSecurityIssues.RemoveWhere(createPrDependencies.Contains);
                break;
            case UpdatePullRequest update:
                var updatePrDependencies = update.DependencyNames.ToHashSet(StringComparer.OrdinalIgnoreCase);
                remainingSecurityIssues.RemoveWhere(updatePrDependencies.Contains);
                break;
        }

        await SendApiMessage(resultMessage);

        // for each security advisory that _didn't_ result in a pr, report it
        foreach (var depName in remainingSecurityIssues)
        {
            await SendApiMessage(new SecurityUpdateNotNeeded(depName));
        }

        var result = new RunResult()
        {
            Base64DependencyFiles = tracker.OriginalDependencyFileContents.OrderBy(kvp => kvp.Key).Select(kvp =>
            {
                var fullPath = kvp.Key.FullyNormalizedRootedPath();
                var rawContent = Encoding.UTF8.GetBytes(kvp.Value);
                if (tracker.OriginalDependencyFileBOMs[kvp.Key])
                {
                    rawContent = Encoding.UTF8.GetPreamble().Concat(rawContent).ToArray();
                }

                return new DependencyFile()
                {
                    Name = Path.GetFileName(fullPath),
                    Content = Convert.ToBase64String(rawContent),
                    ContentEncoding = "base64",
                    Directory = Path.GetDirectoryName(fullPath)!.NormalizePathToUnix(),
                };
            }).ToArray(),
            BaseCommitSha = baseCommitSha,
        };
        return result;
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

    private async Task SendApiMessage(MessageBase? message)
    {
        if (message is null)
        {
            return;
        }

        var report = message.GetReport();
        _logger.Info(report);
        switch (message)
        {
            case JobErrorBase error:
                await _apiHandler.RecordUpdateJobError(error);
                break;
            case CreatePullRequest create:
                await _apiHandler.CreatePullRequest(create);
                break;
            case ClosePullRequest close:
                await _apiHandler.ClosePullRequest(close);
                break;
            case UpdatePullRequest update:
                await _apiHandler.UpdatePullRequest(update);
                break;
            default:
                throw new NotSupportedException($"unsupported api message: {message.GetType().Name}");
        }
    }

    internal static MessageBase? GetPullRequestApiMessage(
        Job job,
        DependencyFile[] updatedFiles,
        ReportedDependency[] updatedDependencies,
        ImmutableArray<UpdateOperationBase> updateOperationsPerformed,
        string baseCommitSha
    )
    {
        var updatedDependencyNames = updateOperationsPerformed.Select(u => u.DependencyName).OrderBy(d => d, StringComparer.OrdinalIgnoreCase).ToArray();
        var updatedDependenciesSet = updatedDependencyNames.ToHashSet(StringComparer.OrdinalIgnoreCase);

        // all pull request dependencies with optional group name
        var existingPullRequests = job.GetAllExistingPullRequests();
        var existingPullRequest = existingPullRequests.FirstOrDefault(pr => pr.Item2.Select(d => d.DependencyName).All(updatedDependenciesSet.Contains));
        if (existingPullRequest is null && updatedFiles.Length == 0)
        {
            // it's possible that we were asked to update a specific package, but it's no longer there; in that case find _that_ specific PR
            var requestedUpdates = job.Dependencies.ToHashSet(StringComparer.OrdinalIgnoreCase);
            existingPullRequest = existingPullRequests.FirstOrDefault(pr => pr.Item2.Select(d => d.DependencyName).All(requestedUpdates.Contains));
        }

        var expectedSecurityUpdateDependencyNames = job.SecurityAdvisories.Select(sa => sa.DependencyName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var isExpectedSecurityUpdate = updatedDependenciesSet.All(expectedSecurityUpdateDependencyNames.Contains);

        if (existingPullRequest is { })
        {
            if (job.UpdatingAPullRequest)
            {
                return new UpdatePullRequest()
                {
                    DependencyGroup = existingPullRequest.Item1,
                    DependencyNames = [.. updatedDependencyNames],
                    UpdatedDependencyFiles = updatedFiles,
                    BaseCommitSha = baseCommitSha,
                    CommitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, updateOperationsPerformed, existingPullRequest.Item1),
                    PrTitle = PullRequestTextGenerator.GetPullRequestTitle(job, updateOperationsPerformed, existingPullRequest.Item1),
                    PrBody = PullRequestTextGenerator.GetPullRequestBody(job, updateOperationsPerformed, existingPullRequest.Item1),
                };
            }
            else
            {
                if (updatedDependenciesSet.Count == 0)
                {
                    // nothing found, close current
                    return new ClosePullRequest()
                    {
                        DependencyNames = [.. existingPullRequest.Item2.Select(d => d.DependencyName)],
                        Reason = "dependency_removed",
                    };
                }
                else
                {
                    // found but no longer required
                    return new ClosePullRequest()
                    {
                        DependencyNames = [.. updatedDependenciesSet],
                        Reason = "up_to_date",
                    };
                }
            }
        }
        else
        {
            if (updatedDependencyNames.Any())
            {
                return new CreatePullRequest()
                {
                    Dependencies = updatedDependencies,
                    UpdatedDependencyFiles = updatedFiles,
                    BaseCommitSha = baseCommitSha,
                    CommitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, updateOperationsPerformed, dependencyGroupName: null),
                    PrTitle = PullRequestTextGenerator.GetPullRequestTitle(job, updateOperationsPerformed, dependencyGroupName: null),
                    PrBody = PullRequestTextGenerator.GetPullRequestBody(job, updateOperationsPerformed, dependencyGroupName: null),
                    DependencyGroup = null,
                };
            }
        }

        return null;
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

    internal static (bool, MessageBase?) UpdatePermittedAndMessage(Job job, Dependency dependency)
    {
        if (dependency.Name.Equals("Microsoft.NET.Sdk", StringComparison.OrdinalIgnoreCase))
        {
            // this can't be updated
            // TODO: pull this out of discovery?
            return (false, null);
        }

        if (dependency.Version is null)
        {
            // if we don't know the version, there's nothing we can do
            // TODO: pull this out of discovery?
            return (false, null);
        }

        var version = NuGetVersion.Parse(dependency.Version);
        var dependencyInfo = GetDependencyInfo(job, dependency);
        var isVulnerable = dependencyInfo.Vulnerabilities.Any(v => v.IsVulnerable(version));
        MessageBase? message = null;
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
                if (isVulnerable)
                {
                    // try to match to existing PR
                    var dependencyVersion = NuGetVersion.Parse(dependency.Version);
                    var existingPullRequests = job.GetAllExistingPullRequests()
                        .Where(pr => pr.Item2.Any(d => d.DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase) && d.DependencyVersion >= dependencyVersion))
                        .ToArray();
                    if (existingPullRequests.Length > 0)
                    {
                        // found a matching pr...
                        if (job.UpdatingAPullRequest)
                        {
                            // ...and we've been asked to update it
                            return true;
                        }
                        else
                        {
                            // ...but no update requested => don't perform any update and report error
                            var existingPrVersion = existingPullRequests[0].Item2.First(d => d.DependencyName.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)).DependencyVersion;
                            message = new PullRequestExistsForLatestVersion(dependency.Name, existingPrVersion.ToString());
                            return false;
                        }
                    }
                    else
                    {
                        // no matching pr...
                        if (job.UpdatingAPullRequest)
                        {
                            // ...but we've been asked to perform an update => no update possible, nothing to report
                            return false;
                        }
                        else
                        {
                            // ...and no update specifically requested => create new
                            return true;
                        }
                    }
                }
                else
                {
                    // not vulnerable => no longer needed
                    var specificJobDependencies = job.SecurityAdvisories
                        .Select(a => a.DependencyName)
                        .Concat(job.Dependencies)
                        .ToHashSet(StringComparer.OrdinalIgnoreCase);
                    if (specificJobDependencies.Contains(dependency.Name))
                    {
                        message = new SecurityUpdateNotNeeded(dependency.Name);
                    }
                }

                return false;
            }
            else
            {
                // not a security update, so only update if...
                // ...we've been explicitly asked to update this
                if (job.Dependencies.Any(d => d.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase)))
                {
                    return true;
                }

                // ...no specific update being performed, do it if it's not transitive
                return !dependency.IsTransitive;
            }
        });

        return (allowed, message);
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
