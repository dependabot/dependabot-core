using NuGetUpdater.Core.Run.PullRequestBodyGenerator;

namespace NuGetUpdater.Core.Test.Run.PullRequestBodyGenerator;

internal class TestHttpFetcher : IHttpFetcher
{
    private readonly Dictionary<string, string> _responses;

    public TestHttpFetcher(Dictionary<string, string> responses)
    {
        _responses = responses;
    }

    public void Dispose()
    {
    }

    public Task<string?> GetStringAsync(string url)
    {
        _responses.TryGetValue(url, out var response);
        return Task.FromResult(response);
    }
}
