using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public interface IApiHandler
{
    Task SendAsync(string endpoint, object body, string method);
}

public static class IApiHandlerExtensions
{
    public static async Task RecordUpdateJobError(this IApiHandler handler, JobErrorBase error)
    {
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

    private static Task PostAsJson(this IApiHandler handler, string endpoint, object body) => handler.SendAsync(endpoint, body, "POST");
    private static Task PatchAsJson(this IApiHandler handler, string endpoint, object body) => handler.SendAsync(endpoint, body, "PATCH");
}
