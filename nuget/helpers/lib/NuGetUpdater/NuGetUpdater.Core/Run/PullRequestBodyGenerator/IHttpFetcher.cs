namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal interface IHttpFetcher : IDisposable
{
    Task<string?> GetStringAsync(string url);
}
