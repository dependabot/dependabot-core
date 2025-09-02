using System.Text.Json.Serialization;

namespace DotNetPackageCorrelation;

public record ReleasesFile
{
    [JsonPropertyName("releases")]
    public Release[] Releases { get; init; } = [];
}
