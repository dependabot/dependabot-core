using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using NuGetUpdater.Core.Run.ApiModel;

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

    public Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger)
    {
        throw new NotImplementedException();
    }
}
