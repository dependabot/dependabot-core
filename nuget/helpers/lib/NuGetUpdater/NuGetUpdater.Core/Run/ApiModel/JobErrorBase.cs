using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public abstract record JobErrorBase
{
    [JsonPropertyName("error-type")]
    public abstract string Type { get; }
    [JsonPropertyName("error-details")]
    public required object Details { get; init; }
}
