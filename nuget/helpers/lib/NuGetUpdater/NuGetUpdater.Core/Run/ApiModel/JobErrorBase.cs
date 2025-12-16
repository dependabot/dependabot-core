using System.Net;
using System.Text;
using System.Text.Json.Serialization;

using Microsoft.Build.Exceptions;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Run.ApiModel;

public abstract record JobErrorBase : MessageBase
{
    public JobErrorBase(string type)
    {
        Type = type;
    }

    [JsonPropertyName("error-type")]
    public string Type { get; }

    [JsonPropertyName("error-details")]
    public Dictionary<string, object> Details { get; init; } = new();

    public override string GetReport()
    {
        var report = new StringBuilder();
        report.AppendLine($"Error type: {Type}");
        report.Append(MarkdownListBuilder.FromObject(Details));
        var fullReport = report.ToString().TrimEnd();
        return fullReport;
    }

    public static JobErrorBase ErrorFromException(Exception ex, string jobId, string currentDirectory)
    {
        switch (ex)
        {
            case BadRequirementException badRequirement:
                return new BadRequirement(badRequirement.Message);
            case BadResponseException badResponse:
                return new PrivateSourceBadResponse([badResponse.Uri], badResponse.Message);
            case DependencyNotFoundException dependencyNotFound:
                return new DependencyNotFound(string.Join(", ", dependencyNotFound.Dependencies));
            case HttpRequestException httpRequest:
                if (httpRequest.StatusCode is null)
                {
                    if (httpRequest.InnerException is HttpIOException ioException &&
                        ioException.HttpRequestError == HttpRequestError.ResponseEnded)
                    {
                        // server hung up on us
                        return new PrivateSourceBadResponse(NuGetContext.GetPackageSourceUrls(currentDirectory), ioException.Message);
                    }

                    return new UnknownError(ex, jobId);
                }

                switch (httpRequest.StatusCode)
                {
                    case HttpStatusCode.Unauthorized:
                    case HttpStatusCode.Forbidden:
                        return new PrivateSourceAuthenticationFailure(NuGetContext.GetPackageSourceUrls(currentDirectory));
                    case HttpStatusCode.TooManyRequests:
                    case HttpStatusCode.ServiceUnavailable:
                        return new PrivateSourceBadResponse(NuGetContext.GetPackageSourceUrls(currentDirectory), httpRequest.Message);
                    default:
                        if ((int)httpRequest.StatusCode / 100 == 5)
                        {
                            return new PrivateSourceBadResponse(NuGetContext.GetPackageSourceUrls(currentDirectory), httpRequest.Message);
                        }

                        return new UnknownError(ex, jobId);
                }
            case InvalidDataException invalidData when invalidData.Message == "Central Directory corrupt.":
                return new PrivateSourceBadResponse(NuGetContext.GetPackageSourceUrls(currentDirectory), invalidData.Message);
            case InvalidProjectFileException invalidProjectFile:
                return new DependencyFileNotParseable(Path.GetRelativePath(currentDirectory, invalidProjectFile.ProjectFile).NormalizePathToUnix());
            case IOException ioException when ioException.Message.Contains("No space left on device", StringComparison.OrdinalIgnoreCase):
                return new OutOfDisk();
            case MissingFileException missingFile:
                return new DependencyFileNotFound(missingFile.FilePath, missingFile.Message);
            case PrivateSourceTimedOutException timeout:
                return new PrivateSourceTimedOut(timeout.Url);
            case UnparseableFileException unparseableFile:
                return new DependencyFileNotParseable(Path.GetRelativePath(currentDirectory, unparseableFile.FilePath).NormalizePathToUnix(), unparseableFile.Message);
            case UpdateNotPossibleException updateNotPossible:
                return new UpdateNotPossible(updateNotPossible.Dependencies);
            default:
                // if a more specific inner exception was encountered, use that, otherwise...
                if (ex.InnerException is not null)
                {
                    var innerError = ErrorFromException(ex.InnerException, jobId, currentDirectory);
                    if (innerError is not UnknownError)
                    {
                        return innerError;
                    }
                }

                // ...return the whole thing
                return new UnknownError(ex, jobId);
        }
    }
}
