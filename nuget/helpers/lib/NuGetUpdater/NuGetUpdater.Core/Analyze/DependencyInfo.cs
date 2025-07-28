using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Analyze;

public sealed record DependencyInfo
{
    public required string Name { get; init; }
    public required string Version { get; init; }
    public required bool IsVulnerable { get; init; }
    public ImmutableArray<Requirement> IgnoredVersions { get; init; }
    public ImmutableArray<SecurityVulnerability> Vulnerabilities { get; init; }
    public ImmutableArray<ConditionUpdateType> IgnoredUpdateTypes { get; init; } = [];
    public Cooldown? Cooldown { get; init; } = null;
}
