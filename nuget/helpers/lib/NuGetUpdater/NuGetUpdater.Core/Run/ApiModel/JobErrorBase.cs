using System.Text.Json.Serialization;

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
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public object? Details { get; init; } = null;
}
