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
                await apiHandler.RecordUpdateJobError(new SecurityUpdateDependencyNotFound());
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
                if (vulnerableDependenciesToUpdate.Length == 0)
                {
                    await apiHandler.RecordUpdateJobError(new SecurityUpdateNotNeeded(dependencyName));
                    continue;
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
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateNotFound(dependency.Name, dependency.Version!));
                        continue;
                    }

                    if (dependencyInfo.IgnoredVersions.Any(ignored => ignored.IsSatisfiedBy(NuGetVersion.Parse(analysisResult.UpdatedVersion))))
                    {
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateIgnored(dependencyName));
                        continue;
                    }

                    var updaterResult = await updaterWorker.RunAsync(repoContentsPath.FullName, projectPath, dependency.Name, dependency.Version!, analysisResult.UpdatedVersion, isTransitive: false);
                    if (updaterResult.Error is not null)
                    {
                        await apiHandler.RecordUpdateJobError(updaterResult.Error);
                        continue;
                    }

                    if (updaterResult.UpdateOperations.Length == 0)
                    {
                        await apiHandler.RecordUpdateJobError(new SecurityUpdateNotPossible(dependencyName, analysisResult.UpdatedVersion, analysisResult.UpdatedVersion, []));
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
                var existingPullRequest = job.GetExistingPullRequestForDependencies(rawDependencies, considerVersions: true);
                if (existingPullRequest is not null && updatedDependencies.Count > 0)
                {
                    await apiHandler.RecordUpdateJobError(new PullRequestExistsForSecurityUpdate(rawDependencies));
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
                });
            }
        }
    }
}
