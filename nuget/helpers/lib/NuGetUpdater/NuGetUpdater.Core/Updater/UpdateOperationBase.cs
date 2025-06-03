using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Utilities;


namespace NuGetUpdater.Core.Updater;

[JsonDerivedType(typeof(DirectUpdate))]
[JsonDerivedType(typeof(PinnedUpdate))]
[JsonDerivedType(typeof(ParentUpdate))]
public abstract record UpdateOperationBase
{
    public abstract string Type { get; }
    public required string DependencyName { get; init; }
    public NuGetVersion? OldVersion { get; init; } = null;
    public required NuGetVersion NewVersion { get; init; }
    public required ImmutableArray<string> UpdatedFiles { get; init; }

    public abstract string GetReport();

    public ReportedDependency ToReportedDependency(IEnumerable<ReportedDependency> previouslyReportedDependencies, IEnumerable<Dependency> updatedDependencies)
    {
        var updatedFilesSet = UpdatedFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var previousDependency = previouslyReportedDependencies
            .Single(d => d.Name.Equals(DependencyName, StringComparison.OrdinalIgnoreCase) && updatedFilesSet.Contains(d.Requirements.Single().File));
        var projectPath = previousDependency.Requirements.Single().File;
        return new ReportedDependency()
        {
            Name = DependencyName,
            Version = NewVersion.ToString(),
            Requirements = [
                new()
                {
                    File = projectPath,
                    Requirement = NewVersion.ToString(),
                    Groups = previousDependency.Requirements.FirstOrDefault()?.Groups ?? [],
                    Source = new()
                    {
                        SourceUrl = updatedDependencies.FirstOrDefault(d => d.Name.Equals(DependencyName, StringComparison.OrdinalIgnoreCase))?.InfoUrl,
                    }
                }
            ],
            PreviousVersion = previousDependency.Version,
            PreviousRequirements = previousDependency.Requirements,
        };
    }

    internal static string GenerateUpdateOperationReport(IEnumerable<UpdateOperationBase> updateOperations)
    {
        var updateMessages = updateOperations.Select(u => u.GetReport()).ToImmutableArray();
        if (updateMessages.Length == 0)
        {
            return string.Empty;
        }

        var report = $"Performed the following updates:\n{string.Join("\n", updateMessages.Select(m => $"- {m}"))}";
        return report;
    }

    internal static ImmutableArray<UpdateOperationBase> NormalizeUpdateOperationCollection(string repoRootPath, IEnumerable<UpdateOperationBase> updateOperations)
    {
        var groupedByKindWithCombinedFiles = updateOperations
            .GroupBy(u => (u.GetType(), u.DependencyName, u.OldVersion, u.NewVersion))
            .Select(g =>
            {
                if (g.Key.Item1 == typeof(DirectUpdate))
                {
                    return new DirectUpdate()
                    {
                        DependencyName = g.Key.DependencyName,
                        OldVersion = g.Key.OldVersion,
                        NewVersion = g.Key.NewVersion,
                        UpdatedFiles = [.. g.SelectMany(u => u.UpdatedFiles)],
                    } as UpdateOperationBase;
                }
                else if (g.Key.Item1 == typeof(PinnedUpdate))
                {
                    return new PinnedUpdate()
                    {
                        DependencyName = g.Key.DependencyName,
                        OldVersion = g.Key.OldVersion,
                        NewVersion = g.Key.NewVersion,
                        UpdatedFiles = [.. g.SelectMany(u => u.UpdatedFiles)],
                    };
                }
                else if (g.Key.Item1 == typeof(ParentUpdate))
                {
                    var parentUpdate = (ParentUpdate)g.First();
                    return new ParentUpdate()
                    {
                        DependencyName = g.Key.DependencyName,
                        OldVersion = g.Key.OldVersion,
                        NewVersion = g.Key.NewVersion,
                        UpdatedFiles = [.. g.SelectMany(u => u.UpdatedFiles)],
                        ParentDependencyName = parentUpdate.ParentDependencyName,
                        ParentNewVersion = parentUpdate.ParentNewVersion,
                    };
                }
                else
                {
                    throw new NotImplementedException(g.Key.Item1.FullName);
                }
            })
            .ToImmutableArray();
        var withNormalizedAndDistinctPaths = groupedByKindWithCombinedFiles
            .Select(u => u with { UpdatedFiles = [.. u.UpdatedFiles.Select(f => Path.GetRelativePath(repoRootPath, f).FullyNormalizedRootedPath()).Distinct(PathComparer.Instance).OrderBy(f => f, StringComparer.Ordinal)] })
            .ToImmutableArray();
        var uniqueUpdateOperations = withNormalizedAndDistinctPaths.Distinct(UpdateOperationBaseComparer.Instance).ToImmutableArray();
        var ordered = uniqueUpdateOperations
            .OrderBy(u => u.GetType().Name)
            .ThenBy(u => u.DependencyName)
            .ThenBy(u => u.OldVersion)
            .ThenBy(u => u.NewVersion)
            .ThenBy(u => u.UpdatedFiles.Length)
            .ThenBy(u => string.Join(",", u.UpdatedFiles))
            .ThenBy(u => u is ParentUpdate parentUpdate ? parentUpdate.ParentDependencyName : string.Empty)
            .ThenBy(u => u is ParentUpdate parentUpdate ? parentUpdate.ParentNewVersion : u.NewVersion)
            .ToImmutableArray();
        return ordered;
    }

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(DependencyName);
        hash.Add(OldVersion);
        hash.Add(NewVersion);
        hash.Add(UpdatedFiles.Length);
        for (int i = 0; i < UpdatedFiles.Length; i++)
        {
            hash.Add(UpdatedFiles[i]);
        }

        return hash.ToHashCode();
    }

    protected string GetString() => $"{GetType().Name} {{ {nameof(DependencyName)} = {DependencyName}, {nameof(NewVersion)} = {NewVersion}, {nameof(UpdatedFiles)} = {string.Join(",", UpdatedFiles)} }}";
}

public record DirectUpdate : UpdateOperationBase
{
    public override string Type => nameof(DirectUpdate);
    public override string GetReport()
    {
        var fromText = OldVersion is null
            ? string.Empty
            : $"from {OldVersion} ";
        return $"Updated {DependencyName} {fromText}to {NewVersion} in {string.Join(", ", UpdatedFiles)}";
    }

    public sealed override string ToString() => GetString();
}

public record PinnedUpdate : UpdateOperationBase
{
    public override string Type => nameof(PinnedUpdate);
    public override string GetReport() => $"Pinned {DependencyName} at {NewVersion} in {string.Join(", ", UpdatedFiles)}";
    public sealed override string ToString() => GetString();
}

public record ParentUpdate : UpdateOperationBase, IEquatable<UpdateOperationBase>
{
    public override string Type => nameof(ParentUpdate);
    public required string ParentDependencyName { get; init; }
    public required NuGetVersion ParentNewVersion { get; init; }

    public override string GetReport() => $"Updated {DependencyName} to {NewVersion} indirectly via {ParentDependencyName}/{ParentNewVersion} in {string.Join(", ", UpdatedFiles)}";

    bool IEquatable<UpdateOperationBase>.Equals(UpdateOperationBase? other)
    {
        if (!base.Equals(other))
        {
            return false;
        }

        if (other is not ParentUpdate otherParentUpdate)
        {
            return false;
        }

        return ParentDependencyName == otherParentUpdate.ParentDependencyName
            && ParentNewVersion == otherParentUpdate.ParentNewVersion;
    }

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(base.GetHashCode());
        hash.Add(ParentDependencyName);
        hash.Add(ParentNewVersion);
        return hash.ToHashCode();
    }

    public sealed override string ToString() => $"{GetType().Name} {{ {nameof(DependencyName)} = {DependencyName}, {nameof(NewVersion)} = {NewVersion}, {nameof(ParentDependencyName)} = {ParentDependencyName}, {nameof(ParentNewVersion)} = {ParentNewVersion}, {nameof(UpdatedFiles)} = {string.Join(",", UpdatedFiles)} }}";
}

public class UpdateOperationBaseComparer : IEqualityComparer<UpdateOperationBase>
{
    public static UpdateOperationBaseComparer Instance = new();

    public bool Equals(UpdateOperationBase? x, UpdateOperationBase? y)
    {
        if (x is null && y is null)
        {
            return true;
        }

        if (x is null || y is null)
        {
            return false;
        }

        if (ReferenceEquals(x, y))
        {
            return true;
        }

        if (x.GetType() != y.GetType())
        {
            return false;
        }

        if (x.DependencyName != y.DependencyName ||
            x.OldVersion != y.OldVersion ||
            x.NewVersion != y.NewVersion ||
            !x.UpdatedFiles.SequenceEqual(y.UpdatedFiles))
        {
            return false;
        }

        if (x is ParentUpdate px && y is ParentUpdate py)
        {
            // the `.GetType()` check above ensures this is safe
            if (px.ParentDependencyName != py.ParentDependencyName ||
                px.ParentNewVersion != py.ParentNewVersion)
            {
                return false;
            }
        }

        return true;
    }

    public int GetHashCode([DisallowNull] UpdateOperationBase obj) => obj.GetHashCode();
}
