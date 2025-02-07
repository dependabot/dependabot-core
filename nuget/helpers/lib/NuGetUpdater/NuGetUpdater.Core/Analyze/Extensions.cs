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
                    if (NuGetVersion.Parse(value.Version!) < NuGetVersion.Parse(dependency.Version!))
                    {
                        dependencies[dependency.Name] = dependency with
                        {
                            TargetFrameworks = [.. value.TargetFrameworks ?? [], .. dependency.TargetFrameworks ?? []]
                        };
                    }
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
