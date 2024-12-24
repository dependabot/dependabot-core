using System.Text.Json.Serialization;

using Semver;

namespace DotNetPackageCorrelation;

public record RuntimePackages
{
    [JsonObjectCreationHandling(JsonObjectCreationHandling.Populate)]
    public SortedDictionary<SemVersion, PackageSet> Runtimes { get; init; } = new(SemVerComparer.Instance);
}
