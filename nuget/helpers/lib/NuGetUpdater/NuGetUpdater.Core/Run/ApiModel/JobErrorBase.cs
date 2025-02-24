using System.Net;
using System.Text.Json.Serialization;

using Microsoft.Build.Exceptions;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run.ApiModel;

public abstract record JobErrorBase
{
    public JobErrorBase(string type)
    {
        Type = type;
    }

    [JsonPropertyName("error-type")]
    public string Type { get; }

    [JsonPropertyName("error-details")]
    public Dictionary<string, object> Details { get; init; } = new();

    public static JobErrorBase ErrorFromException(Exception ex, string jobId, string currentDirectory)
    {
        return ex switch
        {
            BadRequirementException badRequirement => new BadRequirement(badRequirement.Message),
            DependencyNotFoundException dependencyNotFound => new DependencyNotFound(string.Join(", ", dependencyNotFound.Dependencies)),
            HttpRequestException httpRequest => httpRequest.StatusCode switch
            {
                HttpStatusCode.Unauthorized or
                HttpStatusCode.Forbidden => new PrivateSourceAuthenticationFailure(NuGetContext.GetPackageSourceUrls(currentDirectory)),
                _ => new UnknownError(ex, jobId),
            },
            InvalidProjectFileException invalidProjectFile => new DependencyFileNotParseable(invalidProjectFile.ProjectFile),
            MissingFileException missingFile => new DependencyFileNotFound(missingFile.FilePath, missingFile.Message),
            UnparseableFileException unparseableFile => new DependencyFileNotParseable(unparseableFile.FilePath, unparseableFile.Message),
            UpdateNotPossibleException updateNotPossible => new UpdateNotPossible(updateNotPossible.Dependencies),
            _ => new UnknownError(ex, jobId),
        };
    }
}
