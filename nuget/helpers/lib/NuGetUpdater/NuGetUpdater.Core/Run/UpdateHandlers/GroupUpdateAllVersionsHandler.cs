using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class GroupUpdateAllVersionsHandler : IUpdateHandler
{
    private sealed record DirectoryDiscovery(
        string Directory,
        WorkspaceDiscoveryResult DiscoveryResult,
        UpdatedDependencyList UpdatedDependencyList,
        ImmutableArray<(string ProjectPath, Dependency Dependency)> UpdateOperations);

    public static IUpdateHandler Instance { get; } = new GroupUpdateAllVersionsHandler();

    public string TagName => "group_update_all_versions";

    public bool CanHandle(Job job)
    {
        if (job.MultiEcosystemUpdate)
        {
            return true;
        }

        if (job.UpdatingAPullRequest)
        {
            return false;
        }

        if (job.SecurityUpdatesOnly)
        {
            if (job.Dependencies.Length > 1)
            {
                return true;
            }

            if (job.DependencyGroups.Any(g => g.IsSecurity()))
            {
                return true;
            }

            return false;
        }

        return true;
    }

    public async Task HandleAsync(Job job, DirectoryInfo originalRepoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        // group update, do all directories and merge
        // ungrouped update, do each dir separate
        await this.ReportUpdaterStarted(apiHandler);
        await RunGroupedDependencyUpdates(job, originalRepoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
        await RunUngroupedDependencyUpdates(job, originalRepoContentsPath, caseInsensitiveRepoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
    }

    private async Task RunGroupedDependencyUpdates(Job job, DirectoryInfo originalRepoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        var repoContentsPath = caseInsensitiveRepoContentsPath ?? originalRepoContentsPath;
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        foreach (var group in job.DependencyGroups)
        {
            logger.Info($"Starting update for group {group.Name}");
            var directoryDiscoveries = new List<DirectoryDiscovery>();
            foreach (var directory in job.GetAllDirectories(repoContentsPath.FullName))
            {
                var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
                logger.ReportDiscovery(discoveryResult);
                if (discoveryResult.Error is not null)
                {
                    await apiHandler.RecordUpdateJobError(discoveryResult.Error, logger);
                    return;
                }

                var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult, originalRepoContentsPath.FullName, logger, initialFiles);
                await apiHandler.UpdateDependencyList(updatedDependencyList);
                var updateOperations = RunWorker.GetUpdateOperations(discoveryResult).ToImmutableArray();
                directoryDiscoveries.Add(new(directory, discoveryResult, updatedDependencyList, updateOperations));
            }

            if (group.IsGroupedByDependencyName)
            {
                var groupMatcher = group.GetGroupMatcher();
                var directoryDiscoveriesByDependencyName = new Dictionary<string, List<DirectoryDiscovery>>(StringComparer.OrdinalIgnoreCase);
                foreach (var directoryDiscovery in directoryDiscoveries)
                {
                    var matchingOperationsByDependencyName = directoryDiscovery.UpdateOperations
                        .Where(o => job.IsUpdatePermitted(o.Dependency))
                        .Where(o => groupMatcher.IsMatch(o.Dependency.Name))
                        .Where(o => !job.IsDependencyIgnoredByNameOnly(o.Dependency.Name))
                        .GroupBy(o => o.Dependency.Name, StringComparer.OrdinalIgnoreCase);
                    foreach (var matchingOperations in matchingOperationsByDependencyName)
                    {
                        if (!directoryDiscoveriesByDependencyName.TryGetValue(matchingOperations.Key, out var subgroupDiscoveries))
                        {
                            subgroupDiscoveries = [];
                            directoryDiscoveriesByDependencyName.Add(matchingOperations.Key, subgroupDiscoveries);
                        }

                        subgroupDiscoveries.Add(directoryDiscovery with
                        {
                            UpdateOperations = [.. matchingOperations],
                        });
                    }
                }

                foreach (var (dependencyName, subgroupDiscoveries) in directoryDiscoveriesByDependencyName)
                {
                    var subgroup = group.CreateDependencyNameSubgroup(dependencyName);
                    var configuredGroup = job.FindConfiguredDependencyGroup(subgroup.Name);
                    if (configuredGroup is not null)
                    {
                        logger.Info($"Skipping dynamic subgroup {subgroup.Name} because configured group {configuredGroup.Name} has precedence.");
                        continue;
                    }

                    var succeeded = await RunEffectiveGroupUpdate(
                        job,
                        subgroup,
                        subgroupDiscoveries,
                        originalRepoContentsPath,
                        repoContentsPath,
                        initialFiles,
                        baseCommitSha,
                        analyzeWorker,
                        updaterWorker,
                        apiHandler,
                        experimentsManager,
                        logger);
                    if (!succeeded)
                    {
                        return;
                    }
                }
            }
            else
            {
                var succeeded = await RunEffectiveGroupUpdate(
                    job,
                    group,
                    directoryDiscoveries,
                    originalRepoContentsPath,
                    repoContentsPath,
                    initialFiles,
                    baseCommitSha,
                    analyzeWorker,
                    updaterWorker,
                    apiHandler,
                    experimentsManager,
                    logger);
                if (!succeeded)
                {
                    return;
                }
            }
        }
    }

    private static async Task<bool> RunEffectiveGroupUpdate(
        Job job,
        DependencyGroup group,
        IEnumerable<DirectoryDiscovery> directoryDiscoveries,
        DirectoryInfo originalRepoContentsPath,
        DirectoryInfo repoContentsPath,
        HashSet<string> initialFiles,
        string baseCommitSha,
        IAnalyzeWorker analyzeWorker,
        IUpdaterWorker updaterWorker,
        IApiHandler apiHandler,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        logger.Info($"Starting update for effective group {group.Name}");
        var groupMatcher = group.GetGroupMatcher();
        var updateOperationsPerformed = new List<UpdateOperationBase>();
        var updatedDependencies = new List<ReportedDependency>();
        var allUpdatedDependencyFiles = ImmutableArray.Create<DependencyFile>();
        var updatedGroupDirectories = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var directoryDiscovery in directoryDiscoveries)
        {
            var discoveryResult = directoryDiscovery.DiscoveryResult;
            var updatedDependencyList = directoryDiscovery.UpdatedDependencyList;
            var tracker = new ModifiedFilesTracker(originalRepoContentsPath, initialFiles, logger);
            await tracker.StartTrackingAsync(discoveryResult);
            try
            {
                foreach (var (projectPath, dependency) in directoryDiscovery.UpdateOperations)
                {
                    if (!job.IsUpdatePermitted(dependency))
                    {
                        continue;
                    }

                    if (!groupMatcher.IsMatch(dependency.Name))
                    {
                        continue;
                    }

                    if (job.IsDependencyIgnoredByNameOnly(dependency.Name))
                    {
                        logger.Info($"Skipping ignored dependency {dependency.Name}.");
                        continue;
                    }

                    var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [groupMatcher], allowCooldown: true);
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    if (analysisResult.Error is not null)
                    {
                        logger.Error($"Error analyzing {dependency.Name} in {projectPath}: {analysisResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(analysisResult.Error, logger);
                        return false;
                    }

                    if (!analysisResult.CanUpdate)
                    {
                        logger.Info($"No updatable version found for {dependency.Name} in {projectPath}.");
                        continue;
                    }

                    var isUpdateAllowed = groupMatcher.IsAllowedByVersion(NuGetVersion.Parse(dependency.Version!), NuGetVersion.Parse(analysisResult.UpdatedVersion));
                    if (!isUpdateAllowed)
                    {
                        logger.Info($"Dependency {dependency.Name} skipped for group {group.Name} because update type was not allowed.");
                        continue;
                    }

                    var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(projectPath);
                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, dependency.IsTopLevel);
                    if (updaterResult.Error is not null)
                    {
                        logger.Error($"Error updating {dependency.Name} in {projectPath}: {updaterResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(updaterResult.Error, logger);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        continue;
                    }

                    var patchedUpdateOperations = RunWorker.PatchInOldVersions(updaterResult.UpdateOperations, projectDiscovery);
                    var updatedDependenciesForThis = patchedUpdateOperations
                        .Select(o => o.ToReportedDependency(projectPath, updatedDependencyList.Dependencies, analysisResult.UpdatedDependencies))
                        .ToArray();

                    updatedDependencies.AddRange(updatedDependenciesForThis);
                    updateOperationsPerformed.AddRange(patchedUpdateOperations);
                    updatedGroupDirectories.Add(directoryDiscovery.Directory);
                    foreach (var o in patchedUpdateOperations)
                    {
                        logger.Info($"Update operation performed: {o.GetReport(includeFileNames: true)}");
                    }
                }
            }
            finally
            {
                var updatedDependencyFiles = await tracker.StopTrackingAsync(restoreOriginalContents: true);
                allUpdatedDependencyFiles = ModifiedFilesTracker.MergeUpdatedFileSet(allUpdatedDependencyFiles, updatedDependencyFiles);
            }
        }

        if (updateOperationsPerformed.Count > 0)
        {
            var dependencies = updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown));
            var existingPullRequest = group.IsGroupedByDependencyName
                ? job.GetExistingGroupPullRequestForDependencies(dependencies, considerVersions: true, group.Name)
                : job.GetExistingPullRequestForDependencies(dependencies, considerVersions: true);
            if (existingPullRequest is not null)
            {
                logger.Info($"Pull request already exists for {string.Join(", ", existingPullRequest!.Item2.Select(d => $"{d.DependencyName}/{d.DependencyVersion}"))}");
            }
            else
            {
                var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(
                    job,
                    [.. updateOperationsPerformed],
                    group.Name,
                    group.DependencyNameGroupTarget,
                    updatedGroupDirectories);
                var prTitle = PullRequestTextGenerator.GetPullRequestTitle(
                    job,
                    [.. updateOperationsPerformed],
                    group.Name,
                    group.DependencyNameGroupTarget,
                    updatedGroupDirectories);
                var prBody = await PullRequestTextGenerator.GetPullRequestBodyAsync(job, [.. updateOperationsPerformed], [.. updatedDependencies], experimentsManager);
                await apiHandler.CreatePullRequest(new CreatePullRequest()
                {
                    Dependencies = [.. updatedDependencies],
                    UpdatedDependencyFiles = [.. allUpdatedDependencyFiles],
                    BaseCommitSha = baseCommitSha,
                    CommitMessage = commitMessage,
                    PrTitle = prTitle,
                    PrBody = prBody,
                    DependencyGroup = group.Name,
                });
            }
        }

        return true;
    }

    private async Task RunUngroupedDependencyUpdates(Job job, DirectoryInfo originalRepoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        var repoContentsPath = caseInsensitiveRepoContentsPath ?? originalRepoContentsPath;
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        foreach (var directory in job.GetAllDirectories(repoContentsPath.FullName))
        {
            var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
            logger.ReportDiscovery(discoveryResult);
            if (discoveryResult.Error is not null)
            {
                await apiHandler.RecordUpdateJobError(discoveryResult.Error, logger);
                return;
            }

            var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult, originalRepoContentsPath.FullName, logger, initialFiles);
            await apiHandler.UpdateDependencyList(updatedDependencyList);

            var updateOperationsToPerformByDependency = CollectUpdateOperationsByDependency(discoveryResult);
            foreach (var sameDependencySet in updateOperationsToPerformByDependency)
            {
                logger.Info($"Starting dependency update for {sameDependencySet.Key}");
                var updateOperationsPerformed = new List<UpdateOperationBase>();
                var updatedDependencies = new List<ReportedDependency>();
                var tracker = new ModifiedFilesTracker(originalRepoContentsPath, initialFiles, logger);
                await tracker.StartTrackingAsync(discoveryResult);

                foreach (var (projectPath, dependency) in sameDependencySet)
                {
                    if (!job.IsUpdatePermitted(dependency))
                    {
                        continue;
                    }

                    if (job.IsDependencyIgnoredByNameOnly(dependency.Name))
                    {
                        logger.Info($"Skipping ignored dependency {dependency.Name}.");
                        continue;
                    }

                    var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency, groupMatchers: [], allowCooldown: true);
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    if (analysisResult.Error is not null)
                    {
                        logger.Error($"Error analyzing {dependency.Name} in {projectPath}: {analysisResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(analysisResult.Error, logger);
                        return;
                    }

                    if (!analysisResult.CanUpdate)
                    {
                        logger.Info($"No updatable version found for {dependency.Name} in {projectPath}.");
                        continue;
                    }

                    var isSkipped = IsUngroupedDependencySkipped(dependency, analysisResult, job.DependencyGroups, logger);
                    if (isSkipped)
                    {
                        continue;
                    }

                    var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(projectPath);
                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, dependency.IsTopLevel);
                    if (updaterResult.Error is not null)
                    {
                        await apiHandler.RecordUpdateJobError(updaterResult.Error, logger);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        continue;
                    }

                    var patchedUpdateOperations = RunWorker.PatchInOldVersions(updaterResult.UpdateOperations, projectDiscovery);
                    var updatedDependenciesForThis = patchedUpdateOperations
                        .Select(o => o.ToReportedDependency(projectPath, updatedDependencyList.Dependencies, analysisResult.UpdatedDependencies))
                        .ToArray();

                    updatedDependencies.AddRange(updatedDependenciesForThis);
                    updateOperationsPerformed.AddRange(patchedUpdateOperations);
                    foreach (var o in patchedUpdateOperations)
                    {
                        logger.Info($"Update operation performed: {o.GetReport(includeFileNames: true)}");
                    }
                }

                var updatedDependencyFiles = await tracker.StopTrackingAsync(restoreOriginalContents: true);
                if (updateOperationsPerformed.Count > 0)
                {
                    var existingPullRequest = job.GetExistingPullRequestForDependencies(
                        dependencies: updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown)),
                        considerVersions: true);
                    if (existingPullRequest is not null)
                    {
                        logger.Info($"Pull request already exists for {string.Join(", ", existingPullRequest!.Item2.Select(d => $"{d.DependencyName}/{d.DependencyVersion}"))}");
                    }
                    else
                    {
                        var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], null);
                        var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], null);
                        var prBody = await PullRequestTextGenerator.GetPullRequestBodyAsync(job, [.. updateOperationsPerformed], [.. updatedDependencies], experimentsManager);
                        await apiHandler.CreatePullRequest(new CreatePullRequest()
                        {
                            Dependencies = [.. updatedDependencies],
                            UpdatedDependencyFiles = [.. updatedDependencyFiles],
                            BaseCommitSha = baseCommitSha,
                            CommitMessage = commitMessage,
                            PrTitle = prTitle,
                            PrBody = prBody,
                            DependencyGroup = null,
                        });
                    }
                }
            }
        }
    }

    internal static ImmutableArray<IGrouping<string, (string ProjectPath, Dependency Dependency)>> CollectUpdateOperationsByDependency(WorkspaceDiscoveryResult discoveryResult)
    {
        var updateOperationsToPerform = RunWorker.GetUpdateOperations(discoveryResult).ToArray();
        var updateOperationsToPerformByDependency = updateOperationsToPerform
            .GroupBy(o => $"{o.Dependency.Name}/{o.Dependency.Version}".ToLowerInvariant())
            .ToImmutableArray();
        return updateOperationsToPerformByDependency;
    }

    internal static bool IsUngroupedDependencySkipped(Dependency dependency, AnalysisResult dependencyAnalysis, ImmutableArray<DependencyGroup> dependencyGroups, ILogger logger)
    {
        var matcherGroups = dependencyGroups
            .Select(group => (group.Name, Matcher: group.GetGroupMatcher()))
            .Where(pair => pair.Matcher.IsMatch(dependency.Name))
            .ToImmutableArray();
        if (matcherGroups.Length > 0)
        {
            var dynamicGroupNames = dependencyGroups
                .Where(group => group.IsGroupedByDependencyName)
                .Where(group => group.GetGroupMatcher().IsMatch(dependency.Name))
                .Select(group => group.Name)
                .ToArray();
            if (dynamicGroupNames.Length > 0)
            {
                logger.Info($"Dependency {dependency.Name} skipped for ungrouped updates because it's owned by the following dependency-name groups: {string.Join(", ", dynamicGroupNames)}");
                return true;
            }

            // update matches a group by name
            // if any group allows the proposed version range, then it's not allowed in an ungrouped update
            var oldVersion = NuGetVersion.Parse(dependency.Version!);
            var newVersion = NuGetVersion.Parse(dependencyAnalysis.UpdatedVersion);
            var matcherGroupsAllowingVersionRange = matcherGroups
                .Where(pair => pair.Matcher.IsAllowedByVersion(oldVersion, newVersion))
                .ToImmutableArray();
            if (matcherGroupsAllowingVersionRange.Length > 0)
            {
                logger.Info($"Dependency {dependency.Name} skipped for ungrouped updates because it's a member of the following groups: {string.Join(", ", matcherGroupsAllowingVersionRange.Select(pair => pair.Name))}");
                return true;
            }
        }

        return false;
    }
}
