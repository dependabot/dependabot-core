using System.Collections.Immutable;

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
    bool IsUpdate = false);
