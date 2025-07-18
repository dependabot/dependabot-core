using System.Text.Json;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal interface IHttpFetcher : IDisposable
{
    Task<string?> GetStringAsync(string url);
}

internal static class IHttpFetcherExtensions
{
    public static async Task<JsonElement?> GetJsonElementAsync(this IHttpFetcher fetcher, string url)
    {
        var jsonString = await fetcher.GetStringAsync(url);
        if (jsonString is null)
        {
            return null;
        }

        try
        {
            var json = JsonSerializer.Deserialize<JsonElement>(jsonString);
            return json;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
