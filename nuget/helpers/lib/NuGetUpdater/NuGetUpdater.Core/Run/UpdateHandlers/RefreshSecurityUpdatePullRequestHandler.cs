using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

internal class RefreshSecurityUpdatePullRequestHandler : IUpdateHandler
{
    public static IUpdateHandler Instance { get; } = new RefreshSecurityUpdatePullRequestHandler();

    public string TagName => "update_security_pr";

    public bool CanHandle(Job job)
    {
        if (!job.SecurityUpdatesOnly)
        {
            return false;
        }

        if (job.Dependencies.Length == 0)
        {
            return false;
        }

        return job.UpdatingAPullRequest;
    }

    public async Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
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
                .ToDictionary(g => g.Key, g => g.ToArray(), StringComparer.OrdinalIgnoreCase);

            if (groupedUpdateOperationsToPerform.Count == 0)
            {
                await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = job.Dependencies, Reason = "dependencies_removed" });
                continue;
            }

            var missingDependencies = jobDependencies
                .Where(d => !groupedUpdateOperationsToPerform.ContainsKey(d))
                .OrderBy(d => d, StringComparer.OrdinalIgnoreCase)
                .ToImmutableArray();
            if (missingDependencies.Length > 0)
            {
                await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = missingDependencies, Reason = "dependency_removed" });
                continue;
            }

            var tracker = new ModifiedFilesTracker(repoContentsPath);
            await tracker.StartTrackingAsync(discoveryResult);
            foreach (var dependencyGroupToUpdate in groupedUpdateOperationsToPerform)
            {
                var dependencyName = dependencyGroupToUpdate.Key;
                var vulnerableDependenciesToUpdate = dependencyGroupToUpdate.Value
                    .Select(o => (o.ProjectPath, o.Dependency, RunWorker.GetDependencyInfo(job, o.Dependency)))
                    .Where(pair => pair.Item3.IsVulnerable)
                    .ToArray();

                if (vulnerableDependenciesToUpdate.Length < dependencyGroupToUpdate.Value.Length)
                {
                    await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = [dependencyName], Reason = "up_to_date" });
                    return;
                }

                foreach (var (projectPath, dependency, dependencyInfo) in vulnerableDependenciesToUpdate)
                {
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    if (analysisResult.Error is not null)
                    {
                        await apiHandler.RecordUpdateJobError(analysisResult.Error);
                        return;
                    }

                    if (!analysisResult.CanUpdate)
                    {
                        await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = [dependencyName], Reason = "update_no_longer_possible" });
                        return;
                    }

                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: false);
                    if (updaterResult.Error is not null)
                    {
                        await apiHandler.RecordUpdateJobError(updaterResult.Error);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        await apiHandler.ClosePullRequest(new ClosePullRequest() { DependencyNames = [dependencyName], Reason = "update_no_longer_possible" });
                        return;
                    }

                    var previousDependency = updatedDependencyList.Dependencies
                        .Single(d => d.Name == dependency.Name && d.Requirements.Single().File == projectPath);
                    var updatedDependency = new ReportedDependency()
                    {
                        Name = dependency.Name,
                        Version = analysisResult.UpdatedVersion,
                        Requirements = [
                            new ReportedRequirement()
                            {
                                File = projectPath,
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
                    updatedDependencies.Add(updatedDependency);
                    updateOperationsPerformed.AddRange(updaterResult.UpdateOperations);
                }
            }

            var updatedDependencyFiles = await tracker.StopTrackingAsync();
            var rawDependencies = updatedDependencies.Select(d => new Dependency(d.Name, d.Version, DependencyType.Unknown)).ToArray();
            if (rawDependencies.Length > 0)
            {
                var commitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, [.. updateOperationsPerformed], null);
                var prTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperationsPerformed], null);
                var prBody = PullRequestTextGenerator.GetPullRequestBody(job, [.. updateOperationsPerformed], null);

                var existingPullRequest = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: true);
                if (existingPullRequest is not null && updatedDependencies.Count > 0)
                {
                    await apiHandler.UpdatePullRequest(new UpdatePullRequest()
                    {
                        DependencyNames = [.. updatedDependencies.Select(d => d.Name)],
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
                    });
                    continue;
                }
            }
        }
    }
}
