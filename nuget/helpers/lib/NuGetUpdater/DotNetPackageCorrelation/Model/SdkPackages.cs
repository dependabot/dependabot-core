using System.Text.Json.Serialization;

using Semver;

namespace DotNetPackageCorrelation;

public record SdkPackages
{
    [JsonObjectCreationHandling(JsonObjectCreationHandling.Populate)]
    public SortedDictionary<SemVersion, PackageSet> Packages { get; init; } = new(SemVerComparer.Instance);
}
