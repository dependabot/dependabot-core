using System.Net.Http.Headers;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class HttpFetcher : IHttpFetcher
{
    private readonly HttpClient _httpClient;

    public HttpFetcher()
    {
        _httpClient = new HttpClient();
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }

    public async Task<string?> GetStringAsync(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.UserAgent.Add(new ProductInfoHeaderValue("dependabot-core", null));
        var response = await _httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        var result = await response.Content.ReadAsStringAsync();
        return result;
    }
}
