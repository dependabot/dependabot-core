using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run.UpdateHandlers;

public interface IUpdateHandler
{
    string TagName { get; }
    bool CanHandle(Job job);
    Task HandleAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, IDiscoveryWorker discoveryWorker, IAnalyzeWorker analyzeWorker, IUpdaterWorker updaterWorker, IApiHandler apiHandler, ExperimentsManager experimentsManager, ILogger logger);
}

public static class IUpdateHandlerExtensions
{
    public static Task ReportUpdaterStarted(this IUpdateHandler updateHandler, IApiHandler apiHandler) => apiHandler.IncrementMetric(new IncrementMetric()
    {
        Metric = "updater.started",
        Tags = new()
        {
            ["operation"] = updateHandler.TagName,
        }
    });
}
