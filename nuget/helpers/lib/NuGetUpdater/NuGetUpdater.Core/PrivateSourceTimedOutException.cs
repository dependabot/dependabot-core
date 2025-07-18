namespace NuGetUpdater.Core;

internal class PrivateSourceTimedOutException : Exception
{
    public string Url { get; }

    public PrivateSourceTimedOutException(string url)
        : base($"The request to source {url} has timed out.")
    {
        Url = url;
    }
}
