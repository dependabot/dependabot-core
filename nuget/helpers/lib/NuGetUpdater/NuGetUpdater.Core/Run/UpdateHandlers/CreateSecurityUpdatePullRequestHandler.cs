using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class CreateSecurityUpdatePullRequestHandler : IUpdateHandler
{
    public static IUpdateHandler Instance { get; } = new CreateSecurityUpdatePullRequestHandler();

    public string TagName => "create_security_pr";

    public bool CanHandle(Job job)
    {
        // only use this handler if we're creating a new security PR with an explicit list of dependencies
        if (job.UpdatingAPullRequest)
        {
            return false;
        }

        if (job.Dependencies.Length == 0)
        {
            return false;
        }

        return job.SecurityUpdatesOnly;
    }

    public async Task HandleAsync(Job job, DirectoryInfo originalRepoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        var repoContentsPath = caseInsensitiveRepoContentsPath ?? originalRepoContentsPath;
        var jobDependencies = job.Dependencies.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var directory in job.GetAllDirectories())
        {
            var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
            logger.ReportDiscovery(discoveryResult);
            if (discoveryResult.Error is not null)
            {
                await apiHandler.RecordUpdateJobError(discoveryResult.Error, logger);
                return;
            }

            var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult, originalRepoContentsPath.FullName, logger);
            await apiHandler.UpdateDependencyList(updatedDependencyList);
            await this.ReportUpdaterStarted(apiHandler);

            var updateOperationsPerformed = new List<UpdateOperationBase>();
            var updatedDependencies = new List<ReportedDependency>();
            var updateOperationsToPerform = RunWorker.GetUpdateOperations(discoveryResult).ToArray();
            var groupedUpdateOperationsToPerform = updateOperationsToPerform
                .GroupBy(o => o.Dependency.Name, StringComparer.OrdinalIgnoreCase)
                .Where(g => jobDependencies.Contains(g.Key))
                .ToDictionary(g => g.Key, g => g.ToArray(), StringComparer.OrdinalIgnoreCase);

            if (groupedUpdateOperationsToPerform.Count == 0)
            {
                await apiHandler.RecordUpdateJobError(new SecurityUpdateDependencyNotFound(), logger);
                continue;
            }

            logger.Info($"Updating dependencies: {string.Join(", ", groupedUpdateOperationsToPerform.Select(g => g.Key).Distinct().OrderBy(d => d, StringComparer.OrdinalIgnoreCase))}");

            var tracker = new ModifiedFilesTracker(originalRepoContentsPath, logger);
            await tracker.StartTrackingAsync(discoveryResult);
            foreach (var dependencyGroupToUpdate in groupedUpdateOperationsToPerform)
            {
                var dependencyName = dependencyGroupToUpdate.Key;
                var vulnerableCandidateDependenciesToUpdate = dependencyGroupToUpdate.Value
                    .Select(o => (o.ProjectPath, o.Dependency, RunWorker.GetDependencyInfo(job, o.Dependency)))
                    .Where(set => set.Item3.IsVulnerable)
                    .ToArray();
                var vulnerableDependenciesToUpdate = vulnerableCandidateDependenciesToUpdate
                    .Where(o => !job.IsDependencyIgnoredByNameOnly(o.Dependency.Name))
                    .ToArray();
                if (vulnerableDependenciesToUpdate.Length == 0)
                {
                    // no update possible, check backwards to see if it's because of ignore conditions
                    var ignoredUpdates = vulnerableCandidateDependenciesToUpdate
                        .Where(set => set.Dependency.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                        .ToArray();
                    if (ignoredUpdates.Length > 0)
                    {
                        logger.Error($"Cannot update {dependencyName} because all versions are ignored.");
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateIgnored(dependencyName), logger);
                    }
                    else
                    {
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateNotNeeded(dependencyName), logger);
                    }

                    continue;
                }

                foreach (var (projectPath, dependency, dependencyInfo) in vulnerableDependenciesToUpdate)
                {
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
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateNotFound(dependency.Name, dependency.Version!), logger);
                        continue;
                    }

                    logger.Info($"Attempting update of {dependency.Name} from {dependency.Version} to {analysisResult.UpdatedVersion} for {projectPath}.");
                    var projectDiscovery = discoveryResult.GetProjectDiscoveryFromPath(projectPath);
                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, dependency.IsTransitive);
                    if (updaterResult.Error is not null)
                    {
                        logger.Error($"Error updating {dependency.Name} in {projectPath}: {updaterResult.Error.GetReport()}");
                        await apiHandler.RecordUpdateJobError(updaterResult.Error, logger);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        // nothing was done, but we may have already handled it
                        var alreadyHandled = updatedDependencies.Where(updated => updated.Name == dependencyName && updated.Version == analysisResult.UpdatedVersion).Any();
                        if (!alreadyHandled)
                        {
                            logger.Error($"Update of {dependency.Name} in {projectPath} not possible.");
                            await apiHandler.RecordUpdateJobError(new SecurityUpdateNotPossible(dependencyName, analysisResult.UpdatedVersion, analysisResult.UpdatedVersion, []), logger);
                            return;
                        }
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
            }

            var updatedDependencyFiles = await tracker.StopTrackingAsync();
            var rawDependencies = updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown)).ToArray();
            if (rawDependencies.Length > 0)
            {
                var existingPullRequest = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: true);
                if (existingPullRequest is not null)
                {
                    await apiHandler.RecordUpdateJobError(new PullRequestExistsForSecurityUpdate(rawDependencies), logger);
                    continue;
                }
            }

            if (updatedDependencyFiles.Length > 0)
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
