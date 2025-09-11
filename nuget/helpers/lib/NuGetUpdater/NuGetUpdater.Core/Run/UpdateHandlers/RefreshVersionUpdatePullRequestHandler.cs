using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class RefreshVersionUpdatePullRequestHandler : IUpdateHandler
{
    public static IUpdateHandler Instance { get; } = new RefreshVersionUpdatePullRequestHandler();

    public string TagName => "update_version_pr";

    public bool CanHandle(Job job)
    {
        if (job.SecurityUpdatesOnly)
        {
            return false;
        }

        if (job.Dependencies.Length == 0)
        {
            return false;
        }

        return job.UpdatingAPullRequest;
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
            var relevantUpdateOperationsToPerform = updateOperationsToPerform
                .GroupBy(o => o.Dependency.Name, StringComparer.OrdinalIgnoreCase)
                .Where(g => jobDependencies.Contains(g.Key))
                .ToDictionary(g => g.Key, g => g.ToArray(), StringComparer.OrdinalIgnoreCase);

            if (relevantUpdateOperationsToPerform.Count == 0)
            {
                var close = ClosePullRequest.WithDependenciesRemoved(job);
                logger.Info(close.GetReport());
                await apiHandler.ClosePullRequest(close);
                continue;
            }

            var missingDependencies = jobDependencies
                .Where(d => !relevantUpdateOperationsToPerform.ContainsKey(d))
                .OrderBy(d => d, StringComparer.OrdinalIgnoreCase)
                .ToImmutableArray();
            if (missingDependencies.Length > 0)
            {
                var close = ClosePullRequest.WithDependencyRemoved(job);
                logger.Info(close.GetReport());
                await apiHandler.ClosePullRequest(close);
                continue;
            }

            logger.Info($"Updating dependencies: {string.Join(", ", relevantUpdateOperationsToPerform.Select(g => g.Key).Distinct().OrderBy(d => d, StringComparer.OrdinalIgnoreCase))}");

            var tracker = new ModifiedFilesTracker(originalRepoContentsPath, logger);
            await tracker.StartTrackingAsync(discoveryResult);
            foreach (var dependencyUpdatesToPerform in relevantUpdateOperationsToPerform)
            {
                var dependencyName = dependencyUpdatesToPerform.Key;
                var dependencyInfosToUpdate = dependencyUpdatesToPerform.Value
                    .Where(o => !job.IsDependencyIgnoredByNameOnly(o.Dependency.Name))
                    .Select(o => (o.ProjectPath, o.Dependency, RunWorker.GetDependencyInfo(job, o.Dependency, allowCooldown: true)))
                    .ToArray();

                foreach (var (projectPath, dependency, dependencyInfo) in dependencyInfosToUpdate)
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
                        logger.Info($"No update operations performed for {dependency.Name}/{dependency.Version} in project {projectPath}.");
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
            }

            // ensure we did something
            var updatesNotPerformed = jobDependencies
                .Except(updatedDependencies.Select(d => d.Name), StringComparer.OrdinalIgnoreCase)
                .Distinct()
                .OrderBy(d => d, StringComparer.OrdinalIgnoreCase)
                .ToArray();

            if (updatesNotPerformed.Length > 0)
            {
                logger.Info($"No updates performed for: {string.Join(", ", updatesNotPerformed)}");
                await apiHandler.ClosePullRequest(ClosePullRequest.WithUpdateNoLongerPossible(job));
                continue;
            }

            // update or create
            var updatedDependencyFiles = await tracker.StopTrackingAsync();
            var rawDependencies = updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown)).ToArray();
            if (rawDependencies.Length > 0)
            {
                var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], null);
                var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], null);
                var prBody = await PullRequestTextGenerator.GetPullRequestBodyAsync(job, [.. updateOperationsPerformed], [.. updatedDependencies], experimentsManager);

                var existingPullRequest = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: true);
                if (existingPullRequest is not null)
                {
                    await apiHandler.UpdatePullRequest(new UpdatePullRequest()
                    {
                        DependencyNames = [.. jobDependencies.OrderBy(n => n, StringComparer.OrdinalIgnoreCase)],
                        DependencyGroup = null,
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
                        await apiHandler.ClosePullRequest(ClosePullRequest.WithDependenciesChanged(job));
                    }

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
                    continue;
                }
            }
        }
    }
}
