using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class RefreshGroupUpdatePullRequestHandler : IUpdateHandler
{
    public static IUpdateHandler Instance { get; } = new RefreshGroupUpdatePullRequestHandler();

    public string TagName => "update_version_group_pr";

    public bool CanHandle(Job job)
    {
        if (job.Dependencies.Length == 0)
        {
            return false;
        }

        if (job.DependencyGroupToRefresh is null)
        {
            return false;
        }

        if (job.GetAllDirectories().Length > 1)
        {
            return true;
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

        return job.UpdatingAPullRequest;
    }

    public async Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        if (job.DependencyGroupToRefresh is null)
        {
            throw new InvalidOperationException($"{nameof(job.DependencyGroupToRefresh)} must be non-null.");
        }

        var group = job.DependencyGroups.FirstOrDefault(g => g.Name == job.DependencyGroupToRefresh);
        if (group is null)
        {
            throw new InvalidOperationException($"Dependency group {job.DependencyGroupToRefresh} not found.");
        }

        logger.Info($"Starting update for group {group.Name}");

        var groupMatcher = group.GetGroupMatcher();
        var jobDependencies = job.Dependencies.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var directory in job.GetAllDirectories())
        {
            var discoveryResult = await discoveryWorker.RunAsync(repoContentsPath.FullName, directory);
            logger.ReportDiscovery(discoveryResult);
            if (discoveryResult.Error is not null)
            {
                await apiHandler.RecordUpdateJobError(discoveryResult.Error);
                return;
            }

            var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult);
            await apiHandler.UpdateDependencyList(updatedDependencyList);
            await this.ReportUpdaterStarted(apiHandler);

            var updateOperationsPerformed = new List<UpdateOperationBase>();
            var updatedDependencies = new List<ReportedDependency>();
            var updateOperationsToPerform = RunWorker.GetUpdateOperations(discoveryResult).ToArray();
            var groupedUpdateOperationsToPerform = updateOperationsToPerform
                .GroupBy(o => o.Dependency.Name, StringComparer.OrdinalIgnoreCase)
                .Where(g => jobDependencies.Contains(g.Key))
                .Where(g => groupMatcher.IsMatch(g.Key))
                .ToDictionary(g => g.Key, g => g.ToArray(), StringComparer.OrdinalIgnoreCase);
            logger.Info($"Updating dependencies: {string.Join(", ", groupedUpdateOperationsToPerform.Select(g => g.Key).Distinct().OrderBy(d => d, StringComparer.OrdinalIgnoreCase))}");

            var tracker = new ModifiedFilesTracker(repoContentsPath);
            await tracker.StartTrackingAsync(discoveryResult);
            foreach (var dependencyGroupToUpdate in groupedUpdateOperationsToPerform)
            {
                var dependencyName = dependencyGroupToUpdate.Key;
                var relevantDependenciesToUpdate = dependencyGroupToUpdate.Value
                    .Select(o => (o.ProjectPath, o.Dependency, RunWorker.GetDependencyInfo(job, o.Dependency)))
                    .Where(set => !job.IsDependencyIgnored(set.Dependency.Name, set.Dependency.Version!))
                    .ToArray();

                foreach (var (projectPath, dependency, dependencyInfo) in relevantDependenciesToUpdate)
                {
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

                    logger.Info($"Attempting update of {dependency.Name} from {dependency.Version} to {analysisResult.UpdatedVersion} for {projectPath}.");
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
                        logger.Info($"Performed no updates for {dependency.Name} in {projectPath}, but no error reported.");
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
            }

            var updatedDependencyFiles = await tracker.StopTrackingAsync();
            var rawDependencies = updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown)).ToArray();
            if (rawDependencies.Length == 0)
            {
                await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = job.Dependencies, Reason = "update_no_longer_possible" });
                continue;
            }

            var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], null);
            var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], null);
            var prBody = PullRequestTextGenerator.GetPullRequestBody(job, [.. updateOperationsPerformed], null);
            var existingPullRequest = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: true);
            if (existingPullRequest is not null)
            {
                await apiHandler.UpdatePullRequest(new UpdatePullRequest()
                {
                    DependencyNames = [.. updatedDependencies.Select(d => d.Name)],
                    DependencyGroup = group.Name,
                    UpdatedDependencyFiles = [.. updatedDependencyFiles],
                    BaseCommitSha = baseCommitSha,
                    CommitMessage = commitMessage,
                    PrTitle = prTitle,
                    PrBody = prBody,
                });
                continue;
            }
            else
            {
                var existingPrButDifferent = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: false);
                if (existingPrButDifferent is not null)
                {
                    await apiHandler.ClosePullRequest(new ClosePullRequest()
                    {
                        DependencyNames = [.. rawDependencies.Select(d => d.Name)],
                        Reason = "dependencies_changed",
                    });
                }

                await apiHandler.CreatePullRequest(new CreatePullRequest()
                {
                    Dependencies = [.. updatedDependencies],
                    UpdatedDependencyFiles = [.. updatedDependencyFiles],
                    BaseCommitSha = baseCommitSha,
                    CommitMessage = commitMessage,
                    PrTitle = prTitle,
                    PrBody = prBody,
                    DependencyGroup = group.Name,
                });
                continue;
            }
        }
    }
}
