using System.Text.Json.Serialization;

using Semver;

namespace DotNetPackageCorrelation;

public record Sdk
{
    [JsonPropertyName("version")]
    public required SemVersion? Version { get; init; }
    [JsonPropertyName("runtime-version")]
    public SemVersion? RuntimeVersion { get; init; }
}
