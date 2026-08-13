using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Versioning;

using NuGetUpdater.Core;

internal static class Extensions
{
    public static ImmutableArray<Dependency> GetDependencies(this ImmutableDictionary<string, ImmutableArray<Dependency>> dependenciesByTfm)
    {
        Dictionary<string, Dependency> dependencies = [];
        foreach (var (_framework, dependenciesForTfm) in dependenciesByTfm)
        {
            foreach (var dependency in dependenciesForTfm)
            {
                if (dependencies.TryGetValue(dependency.Name, out Dependency? value))
                {
                    var selectedDependency = NuGetVersion.Parse(value.Version!) < NuGetVersion.Parse(dependency.Version!)
                        ? dependency
                        : value;
                    var assetFlags = (value.AssetFlags ?? [])
                        .Concat(dependency.AssetFlags ?? [])
                        .GroupBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase)
                        .ToImmutableDictionary(
                            group => group.Key,
                            group => group.Select(kvp => kvp.Value).Aggregate((left, right) => left | right),
                            StringComparer.OrdinalIgnoreCase);
                    dependencies[dependency.Name] = selectedDependency with
                    {
                        TargetFrameworks = value.TargetFrameworks
                            .GetValueOrDefault()
                            .Concat(dependency.TargetFrameworks.GetValueOrDefault())
                            .Select(targetFramework => NuGetFramework.Parse(targetFramework).GetShortFolderName())
                            .Distinct(StringComparer.OrdinalIgnoreCase)
                            .ToImmutableArray(),
                        AssetFlags = assetFlags,
                    };
                }
                else
                {
                    dependencies.Add(dependency.Name, dependency);
                }
            }
        }

        return [.. dependencies.Values];
    }
}
