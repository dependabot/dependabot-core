using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using static NuGet.Commands.TransitiveNoWarnUtils;

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

                    var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
                    var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                    if (analysisResult.Error is not null)
                    {
                        await apiHandler.RecordUpdateJobError(analysisResult.Error);
                        return;
                    }

                    if (!analysisResult.CanUpdate)
                    {
                        continue;
                    }

                    if (dependencyInfo.IgnoredVersions.Any(ignored => ignored.IsSatisfiedBy(NuGetVersion.Parse(analysisResult.UpdatedVersion))))
                    {
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
                        continue;
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

                var dependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
                var analysisResult = await analyzeWorker.RunAsync(repoContentsPath.FullName, discoveryResult, dependencyInfo);
                if (analysisResult.Error is not null)
                {
                    await apiHandler.RecordUpdateJobError(analysisResult.Error);
                    return;
                }

                if (!analysisResult.CanUpdate)
                {
                    continue;
                }

                if (dependencyInfo.IgnoredVersions.Any(ignored => ignored.IsSatisfiedBy(NuGetVersion.Parse(analysisResult.UpdatedVersion))))
                {
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
                    continue;
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
                });
            }
        }
    }
}
