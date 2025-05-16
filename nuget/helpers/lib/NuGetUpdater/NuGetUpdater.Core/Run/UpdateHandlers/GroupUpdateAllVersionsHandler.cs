using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using NuGetUpdater.Core.Run.ApiModel;

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

    public Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        if (job.DependencyGroups.Length > 0)
        {
            return RunGroupedDependencyUpdates(job, repoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
        }

        return RunUngroupedDependencyUpdates(job, repoContentsPath, baseCommitSha, discoveryWorker, analyzeWorker, updaterWorker, apiHandler, experimentsManager, logger);
    }

    private async Task RunGroupedDependencyUpdates(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {

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

            var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discoveryResult);
            await apiHandler.UpdateDependencyList(updatedDependencyList);
            await this.ReportUpdaterStarted(apiHandler);
        }
    }
}
