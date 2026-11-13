namespace NuGetUpdater.Core.Test.Run.PullRequestBodyGenerator;

internal class TestStringResponseHttpFetcher : TestHttpFetcher
{
    public TestStringResponseHttpFetcher(Dictionary<string, string> responses)
        : base(BuildResponseGenerator(responses))
    {
    }

    private static Func<string, string?> BuildResponseGenerator(Dictionary<string, string> responses)
    {
        return new Func<string, string?>(url =>
        {
            if (responses.TryGetValue(url, out var response))
            {
                return response;
            }

            return null;
        });
    }
}
