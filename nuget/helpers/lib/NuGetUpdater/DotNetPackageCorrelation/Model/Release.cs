using System.Collections.Immutable;
using System.Text.Json.Serialization;

namespace DotNetPackageCorrelation;

public record Release
{
    [JsonPropertyName("sdk")]
    public Sdk? Sdk { get; init; }

    [JsonPropertyName("sdks")]
    public ImmutableArray<Sdk>? Sdks { get; init; } = [];
}

public static class ReleaseExtensions
{
    public static IEnumerable<Sdk> GetSdks(this Release release)
    {
        if (release.Sdk is not null)
        {
            yield return release.Sdk;
        }
        foreach (var sdk in release.Sdks ?? [])
        {
            yield return sdk;
        }
    }
}
