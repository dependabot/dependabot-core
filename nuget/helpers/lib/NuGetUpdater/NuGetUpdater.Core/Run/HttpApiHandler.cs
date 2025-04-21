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

    public async Task ClosePullRequest(ClosePullRequest closePullRequest)
    {
        await PostAsJson("close_pull_request", closePullRequest);
    }

    public async Task UpdatePullRequest(UpdatePullRequest updatePullRequest)
    {
        await PostAsJson("update_pull_request", updatePullRequest);
    }

    public async Task MarkAsProcessed(MarkAsProcessed markAsProcessed)
    {
        await PatchAsJson("mark_as_processed", markAsProcessed);
    }

    internal static string Serialize(object body)
    {
        var wrappedBody = new
        {
            Data = body
        };
        var payload = JsonSerializer.Serialize(wrappedBody, SerializerOptions);
        return payload;
    }

    private Task PostAsJson(string endpoint, object body) => SendAsJson(endpoint, body, "POST");
    private Task PatchAsJson(string endpoint, object body) => SendAsJson(endpoint, body, "PATCH");

    private async Task SendAsJson(string endpoint, object body, string method)
    {
        var uri = $"{_apiUrl}/update_jobs/{_jobId}/{endpoint}";
        var payload = Serialize(body);
        var content = new StringContent(payload, Encoding.UTF8, "application/json");
        var httpMethod = new HttpMethod(method);
        var message = new HttpRequestMessage(httpMethod, uri)
        {
            Content = content
        };
        var response = await HttpClient.SendAsync(message);
        var _ = response.EnsureSuccessStatusCode();
    }
}
