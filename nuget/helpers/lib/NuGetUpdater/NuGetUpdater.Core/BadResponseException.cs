namespace NuGetUpdater.Core;

internal class BadResponseException : Exception
{
    public string Uri { get; }

    public BadResponseException(string message, string uri)
        : base(message)
    {
        Uri = uri;
    }
}
