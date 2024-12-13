using System.Collections.Immutable;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run.ApiModel;

public record Advisory
{
    public required string DependencyName { get; init; }
    public ImmutableArray<Requirement>? AffectedVersions { get; init; } = null;
    public ImmutableArray<Requirement>? PatchedVersions { get; init; } = null;
    public ImmutableArray<Requirement>? UnaffectedVersions { get; init; } = null;
}
