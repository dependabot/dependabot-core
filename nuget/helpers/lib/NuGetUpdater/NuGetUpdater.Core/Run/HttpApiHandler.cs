using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run;

public class HttpApiHandler : IApiHandler, IApiRetryDelayProvider
{
    private static readonly HttpClient HttpClient = new();

    public static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly string _apiUrl;
    private readonly string _jobId;
    private readonly Func<TimeSpan, Task> _retryDelay;

    public HttpApiHandler(string apiUrl, string jobId)
        : this(apiUrl, jobId, Task.Delay)
    {
    }

    internal HttpApiHandler(string apiUrl, string jobId, Func<TimeSpan, Task> retryDelay)
    {
        _apiUrl = apiUrl.TrimEnd('/');
        _jobId = jobId;
        _retryDelay = retryDelay;
    }

    Task IApiRetryDelayProvider.DelayAsync(TimeSpan delay) => _retryDelay(delay);

    public async Task SendAsync(string endpoint, object body, string method)
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
        if (!response.IsSuccessStatusCode)
        {
            var responseContent = await response.Content.ReadAsStringAsync();
            if (!string.IsNullOrEmpty(responseContent))
            {
                responseContent = string.Concat(": ", responseContent);
            }

            throw new HttpRequestException(message: $"{(int)response.StatusCode} ({response.StatusCode}){responseContent}", inner: null, statusCode: response.StatusCode);
        }
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
}
