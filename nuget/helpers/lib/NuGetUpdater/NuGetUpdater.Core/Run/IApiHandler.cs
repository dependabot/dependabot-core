using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public interface IApiHandler
{
    Task SendAsync(string endpoint, object body, string method);
}

public static class IApiHandlerExtensions
{
    public static async Task RecordUpdateJobError(this IApiHandler handler, JobErrorBase error, ILogger logger)
    {
        var errorReport = error.GetReport();
        logger.Error(errorReport);
        await handler.PostAsJson("record_update_job_error", error);
        if (error is UnknownError unknown)
        {
            await handler.PostAsJson("record_update_job_unknown_error", error);
            var increment = new IncrementMetric()
            {
                Metric = "updater.update_job_unknown_error",
                Tags =
                {
                    ["package_manager"] = "nuget",
                    ["class_name"] = unknown.Exception.GetType().Name
                },
            };
            await handler.IncrementMetric(increment);
        }
    }

    public static Task UpdateDependencyList(this IApiHandler handler, UpdatedDependencyList updatedDependencyList) => handler.PostAsJson("update_dependency_list", updatedDependencyList);
    public static Task IncrementMetric(this IApiHandler handler, IncrementMetric incrementMetric) => handler.PostAsJson("increment_metric", incrementMetric);
    public static Task CreatePullRequest(this IApiHandler handler, CreatePullRequest createPullRequest) => handler.PostAsJson("create_pull_request", createPullRequest);
    public static Task ClosePullRequest(this IApiHandler handler, ClosePullRequest closePullRequest) => handler.PostAsJson("close_pull_request", closePullRequest);
    public static Task UpdatePullRequest(this IApiHandler handler, UpdatePullRequest updatePullRequest) => handler.PostAsJson("update_pull_request", updatePullRequest);
    public static Task MarkAsProcessed(this IApiHandler handler, MarkAsProcessed markAsProcessed) => handler.PatchAsJson("mark_as_processed", markAsProcessed);

    private static Task PostAsJson(this IApiHandler handler, string endpoint, object body) => handler.WithRetries(() => handler.SendAsync(endpoint, body, "POST"));
    private static Task PatchAsJson(this IApiHandler handler, string endpoint, object body) => handler.WithRetries(() => handler.SendAsync(endpoint, body, "PATCH"));

    private const int MaxRetries = 3;
    private const int MinRetryDelay = 3;
    private const int MaxRetryDelay = 10;

    private static async Task WithRetries(this IApiHandler handler, Func<Task> action)
    {
        var retryCount = 0;
        while (true)
        {
            try
            {
                await action();
                return;
            }
            catch (HttpRequestException ex)
            when (retryCount < MaxRetries &&
                (ex.StatusCode is null || ((int)ex.StatusCode) / 100 == 5))
            {
                retryCount++;
                await Task.Delay(TimeSpan.FromSeconds(Random.Shared.Next(MinRetryDelay, MaxRetryDelay)));
            }
        }
    }
}
