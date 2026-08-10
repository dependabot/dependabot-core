using System.Collections.Immutable;

using NuGet.LibraryModel;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

public sealed record Dependency(
    string Name,
    string? Version,
    DependencyType Type,
    EvaluationResult? EvaluationResult = null,
    ImmutableArray<string>? TargetFrameworks = null,
    bool IsTopLevel = true,
    bool IsUpdate = false,
    string? InfoUrl = null,
    ImmutableDictionary<string, LibraryIncludeFlags>? AssetFlags = null) : IEquatable<Dependency>
{
    public bool Equals(Dependency? other)
    {
        if (other is null)
        {
            return false;
        }

        if (ReferenceEquals(this, other))
        {
            return true;
        }

        return Name == other.Name &&
               Version == other.Version &&
               Type == other.Type &&
               EvaluationResult == other.EvaluationResult &&
               TargetFrameworks.SequenceEqual(other.TargetFrameworks) &&
               IsTopLevel == other.IsTopLevel &&
               IsUpdate == other.IsUpdate &&
               InfoUrl == other.InfoUrl &&
               AssetFlagsEqual(AssetFlags, other.AssetFlags);
    }

    public override int GetHashCode()
    {
        HashCode hash = new();
        hash.Add(Name);
        hash.Add(Version);
        hash.Add(Type);
        hash.Add(EvaluationResult);
        hash.Add(TargetFrameworks);
        hash.Add(IsTopLevel);
        hash.Add(IsUpdate);
        hash.Add(InfoUrl);
        if (AssetFlags is not null)
        {
            foreach (var (targetFramework, flags) in AssetFlags.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase))
            {
                hash.Add(targetFramework, StringComparer.OrdinalIgnoreCase);
                hash.Add(flags);
            }
        }

        return hash.ToHashCode();
    }

    private static bool AssetFlagsEqual(
        ImmutableDictionary<string, LibraryIncludeFlags>? left,
        ImmutableDictionary<string, LibraryIncludeFlags>? right)
    {
        if (left is null || left.Count == 0)
        {
            return right is null || right.Count == 0;
        }

        if (right is null || left.Count != right.Count)
        {
            return false;
        }

        return left.All(kvp => right.TryGetValue(kvp.Key, out var rightValue) && kvp.Value == rightValue);
    }
}
