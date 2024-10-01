using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public class HttpApiHandler : IApiHandler
{
    private static readonly HttpClient HttpClient = new();

    public static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly string _apiUrl;
    private readonly string _jobId;

    public HttpApiHandler(string apiUrl, string jobId)
    {
        _apiUrl = apiUrl.TrimEnd('/');
        _jobId = jobId;
    }

    public async Task RecordUpdateJobError(JobErrorBase error)
    {
        await PostAsJson("record_update_job_error", error);
    }

    public async Task UpdateDependencyList(UpdatedDependencyList updatedDependencyList)
    {
        await PostAsJson("update_dependency_list", updatedDependencyList);
    }

    public async Task IncrementMetric(IncrementMetric incrementMetric)
    {
        await PostAsJson("increment_metric", incrementMetric);
    }

    public async Task CreatePullRequest(CreatePullRequest createPullRequest)
    {
        await PostAsJson("create_pull_request", createPullRequest);
    }

    public async Task MarkAsProcessed(MarkAsProcessed markAsProcessed)
    {
        await PostAsJson("mark_as_processed", markAsProcessed);
    }

    private async Task PostAsJson(string endpoint, object body)
    {
        var wrappedBody = new
        {
            Data = body,
        };
        var payload = JsonSerializer.Serialize(wrappedBody, SerializerOptions);
        var content = new StringContent(payload, Encoding.UTF8, "application/json");
        var response = await HttpClient.PostAsync($"{_apiUrl}/update_jobs/{_jobId}/{endpoint}", content);
        var _ = response.EnsureSuccessStatusCode();
    }
}
