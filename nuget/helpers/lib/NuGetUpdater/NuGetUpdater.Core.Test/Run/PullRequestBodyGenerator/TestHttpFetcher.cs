using NuGetUpdater.Core.Run.PullRequestBodyGenerator;

namespace NuGetUpdater.Core.Test.Run.PullRequestBodyGenerator;

internal class TestHttpFetcher : IHttpFetcher
{
    private readonly Func<string, string?> _responseHandler;

    public TestHttpFetcher(Func<string, string?> responseHandler)
    {
        _responseHandler = responseHandler;
    }

    public void Dispose()
    {
    }

    public Task<string?> GetStringAsync(string url)
    {
        var response = _responseHandler(url);
        return Task.FromResult(response);
    }
}
