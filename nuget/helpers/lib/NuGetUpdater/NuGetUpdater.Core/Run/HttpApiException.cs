using System.Net;

namespace NuGetUpdater.Core.Run;

public sealed class HttpApiException : HttpRequestException
{
    public string Method { get; }
    public string Endpoint { get; }
    public string? ResponseContent { get; }

    public HttpApiException(string method, string endpoint, HttpStatusCode statusCode, string? responseContent)
        : base(BuildMessage(method, endpoint, statusCode, responseContent), inner: null, statusCode: statusCode)
    {
        Method = method;
        Endpoint = endpoint;
        ResponseContent = string.IsNullOrEmpty(responseContent) ? null : responseContent;
    }

    private static string BuildMessage(string method, string endpoint, HttpStatusCode statusCode, string? responseContent)
    {
        var message = $"{method} {endpoint} failed with {(int)statusCode} ({statusCode})";
        return string.IsNullOrEmpty(responseContent) ? message : $"{message}: {responseContent}";
    }
}
