using System.Text.Json.Serialization;

using Semver;

namespace DotNetPackageCorrelation;

public record PackageSet
{
    [JsonObjectCreationHandling(JsonObjectCreationHandling.Populate)]
    public SortedDictionary<string, SemVersion> Packages { get; init; } = new(StringComparer.OrdinalIgnoreCase);
}
