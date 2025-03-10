using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public record CommitOptions
{
    public string? Prefix { get; init; } = null;
    public string? PrefixDevelopment { get; init; } = null;

    [JsonConverter(typeof(CommitOptions_IncludeScopeConverter))]
    public bool IncludeScope { get; init; } = false;
}
