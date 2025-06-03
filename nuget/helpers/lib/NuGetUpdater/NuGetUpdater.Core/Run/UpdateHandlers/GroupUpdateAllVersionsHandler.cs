using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class GroupUpdateAllVersionsHandler : IUpdateHandler
{
    public static IUpdateHandler Instance { get; } = new GroupUpdateAllVersionsHandler();

    public string TagName => "group_update_all_versions";

    public bool CanHandle(Job job)
    {
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

    public async Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        // group update, do all directories and merge
        // ungrouped update, do each dir separate
        await this.ReportUpdaterStarted(apiHandler);
        if (job.DependencyGroups.Length > 0)
        {
            await RunGroupedDependencyUpdates(job, repoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
        }
        else
        {
            await RunUngroupedDependencyUpdates(job, repoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
        }
    }

    private async Task RunGroupedDependencyUpdates(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        foreach (var group in job.DependencyGroups)
        {
            logger.Info($"Starting update for group {group.Name}");
            var groupMatcher = group.GetGroupMatcher();
            var updateOperationsPerformed = new List<UpdateOperationBase>();
            var updatedDependencies = new List<ReportedDependency>();
            var allUpdatedDependencyFiles = ImmutableArray.Create<DependencyFile>();
            foreach (var directory in job.GetAllDirectories())
            {
                var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
                logger.ReportDiscovery(discoveryResult);
                if (discoveryResult.Error is not null)
                {
                    await apiHandler.RecordUpdateJobError(discoveryResult.Error);
                    return;
                }

                var tracker = new ModifiedFilesTracker(repoContentsPath);
                await tracker.StartTrackingAsync(discoveryResult);

                var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult);
                await apiHandler.UpdateDependencyList(updatedDependencyList);

                var updateOperationsToPerform = RunWorker.GetUpdateOperations(discoveryResult).ToArray();
                foreach (var (projectPath, dependency) in updateOperationsToPerform)
                {
                    if (dependency.IsTransitive)
                    {
                        continue;
                    }

                    if (!groupMatcher.IsMatch(dependency.Name))
                    {
                        continue;
                    }

                    if (job.IsDependencyIgnored(dependency.Name, dependency.Version!))
                    {
                        logger.Info($"Skipping ignored dependency {dependency.Name}/{dependency.Version}.");
                        continue;
                    }

                    var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    if (analysisResult.Error is not null)
                    {
                        logger.Error($"Error analyzing {dependency.Name} in {projectPath}: {analysisResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(analysisResult.Error);
                        return;
                    }

                    if (!analysisResult.CanUpdate)
                    {
                        logger.Info($"No updatable version found for {dependency.Name} in {projectPath}.");
                        continue;
                    }

                    if (dependencyInfo.IgnoredVersions.Any(ignored => ignored.IsSatisfiedBy(NuGetVersion.Parse(analysisResult.UpdatedVersion))))
                    {
                        logger.Info($"Cannot update {dependency.Name} for {projectPath} because all versions are ignored.");
                        continue;
                    }

                    var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(projectPath);
                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, dependency.IsTransitive);
                    if (updaterResult.Error is not null)
                    {
                        logger.Error($"Error updating {dependency.Name} in {projectPath}: {updaterResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(updaterResult.Error);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        continue;
                    }

                    var patchedUpdateOperations = RunWorker.PatchInOldVersions(updaterResult.UpdateOperations, projectDiscovery);
                    var updatedDependenciesForThis = patchedUpdateOperations
                        .Select(o => o.ToReportedDependency(updatedDependencyList.Dependencies, analysisResult.UpdatedDependencies))
                        .ToArray();

                    updatedDependencies.AddRange(updatedDependenciesForThis);
                    updateOperationsPerformed.AddRange(patchedUpdateOperations);
                    foreach (var o in patchedUpdateOperations)
                    {
                        logger.Info($"Update operation performed: {o.GetReport()}");
                    }
                }

                var updatedDependencyFiles = await tracker.StopTrackingAsync();
                allUpdatedDependencyFiles = ModifiedFilesTracker.MergeUpdatedFileSet(allUpdatedDependencyFiles, updatedDependencyFiles);
            }

            if (updateOperationsPerformed.Count > 0)
            {
                var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], group.Name);
                var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], group.Name);
                var prBody = PullRequestTextGenerator.GetPullRequestBody(job, [.. updateOperationsPerformed], group.Name);
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
    }

    private async Task RunUngroupedDependencyUpdates(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        foreach (var directory in job.GetAllDirectories())
        {
            var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
            logger.ReportDiscovery(discoveryResult);
            if (discoveryResult.Error is not null)
            {
                await apiHandler.RecordUpdateJobError(discoveryResult.Error);
                return;
            }

            var tracker = new ModifiedFilesTracker(repoContentsPath);
            await tracker.StartTrackingAsync(discoveryResult);

            var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult);
            await apiHandler.UpdateDependencyList(updatedDependencyList);

            var updateOperationsPerformed = new List<UpdateOperationBase>();
            var updatedDependencies = new List<ReportedDependency>();
            var updateOperationsToPerform = RunWorker.GetUpdateOperations(discoveryResult).ToArray();
            foreach (var (projectPath, dependency) in updateOperationsToPerform)
            {
                if (dependency.IsTransitive)
                {
                    continue;
                }

                if (job.IsDependencyIgnored(dependency.Name, dependency.Version!))
                {
                    logger.Info($"Skipping ignored dependency {dependency.Name}/{dependency.Version}.");
                    continue;
                }

                var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
                var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                if (analysisResult.Error is not null)
                {
                    logger.Error($"Error analyzing {dependency.Name} in {projectPath}: {analysisResult.Error.GetReport()}");
                    await apiHandler.RecordUpdateJobError(analysisResult.Error);
                    return;
                }

                if (!analysisResult.CanUpdate)
                {
                    logger.Info($"No updatable version found for {dependency.Name} in {projectPath}.");
                    continue;
                }

                if (dependencyInfo.IgnoredVersions.Any(ignored => ignored.IsSatisfiedBy(NuGetVersion.Parse(analysisResult.UpdatedVersion))))
                {
                    logger.Info($"Cannot update {dependency.Name} for {projectPath} because all versions are ignored.");
                    continue;
                }

                var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(projectPath);
                var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, dependency.IsTransitive);
                if (updaterResult.Error is not null)
                {
                    await apiHandler.RecordUpdateJobError(updaterResult.Error);
                    continue;
                }

                if (updaterResult.UpdateOperations.Length == 0)
                {
                    continue;
                }

                var patchedUpdateOperations = RunWorker.PatchInOldVersions(updaterResult.UpdateOperations, projectDiscovery);
                var updatedDependenciesForThis = patchedUpdateOperations
                        .Select(o => o.ToReportedDependency(updatedDependencyList.Dependencies, analysisResult.UpdatedDependencies))
                        .ToArray();

                updatedDependencies.AddRange(updatedDependenciesForThis);
                updateOperationsPerformed.AddRange(patchedUpdateOperations);
                foreach (var o in patchedUpdateOperations)
                {
                    logger.Info($"Update operation performed: {o.GetReport()}");
                }
            }

            var updatedDependencyFiles = await tracker.StopTrackingAsync();
            if (updateOperationsPerformed.Count > 0)
            {
                var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], null);
                var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], null);
                var prBody = PullRequestTextGenerator.GetPullRequestBody(job, [.. updateOperationsPerformed], null);
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
