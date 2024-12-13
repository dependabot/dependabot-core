using System.Text.Json.Serialization;

namespace DotNetPackageCorrelation;

public record Release
{
    [JsonPropertyName("sdk")]
    public required Sdk Sdk { get; init; }
}
