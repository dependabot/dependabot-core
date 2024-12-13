using System.Collections.Immutable;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

public sealed record Dependency(
    string Name,
    string? Version,
    DependencyType Type,
    EvaluationResult? EvaluationResult = null,
    ImmutableArray<string>? TargetFrameworks = null,
    bool IsDevDependency = false,
    bool IsDirect = false,
    bool IsTransitive = false,
    bool IsOverride = false,
    bool IsUpdate = false,
    string? InfoUrl = null) : IEquatable<Dependency>
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
               IsDevDependency == other.IsDevDependency &&
               IsDirect == other.IsDirect &&
               IsTransitive == other.IsTransitive &&
               IsOverride == other.IsOverride &&
               IsUpdate == other.IsUpdate &&
               InfoUrl == other.InfoUrl;
    }

    public override int GetHashCode()
    {
        HashCode hash = new();
        hash.Add(Name);
        hash.Add(Version);
        hash.Add(Type);
        hash.Add(EvaluationResult);
        hash.Add(TargetFrameworks);
        hash.Add(IsDevDependency);
        hash.Add(IsDirect);
        hash.Add(IsTransitive);
        hash.Add(IsOverride);
        hash.Add(IsUpdate);
        hash.Add(InfoUrl);
        return hash.ToHashCode();
    }
}
