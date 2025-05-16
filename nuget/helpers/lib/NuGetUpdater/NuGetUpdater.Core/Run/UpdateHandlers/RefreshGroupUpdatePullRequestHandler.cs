using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using NuGetUpdater.Core.Run.ApiModel;

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

    public Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        throw new NotImplementedException();
    }
}
