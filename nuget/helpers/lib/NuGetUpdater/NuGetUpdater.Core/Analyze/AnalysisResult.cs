using System.Collections.Immutable;

namespace NuGetUpdater.Core.Analyze;

public record AnalysisResult : NativeResult
{
    public required string UpdatedVersion { get; init; }
    public bool CanUpdate { get; init; }
    public bool VersionComesFromMultiDependencyProperty { get; init; }
    public required ImmutableArray<Dependency> UpdatedDependencies { get; init; }
}
