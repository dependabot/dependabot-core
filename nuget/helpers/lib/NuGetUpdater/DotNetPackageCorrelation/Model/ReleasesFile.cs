using System.Text.Json.Serialization;

namespace DotNetPackageCorrelation;

public record ReleasesFile
{
    [JsonPropertyName("releases")]
    public required Release[] Releases { get; init; }
}
