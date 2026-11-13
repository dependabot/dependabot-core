using Microsoft.Extensions.FileSystemGlobbing;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record AllowedUpdate
{
    public DependencyType DependencyType { get; init; } = DependencyType.All;
    public string? DependencyName { get; init; } = null;
    public UpdateType UpdateType { get; init; } = UpdateType.All;
    public ConditionUpdateType[]? UpdateTypes { get; init; } = null;

    internal bool MatchesDependencyName(string dependencyName) =>
        DependencyName is null ||
        new Matcher(StringComparison.OrdinalIgnoreCase)
            .AddInclude(DependencyName)
            .Match(dependencyName)
            .HasMatches;
}

public enum DependencyType
{
    All,
    Direct,
    Indirect,
    Development,
    Production,
}

public enum UpdateType
{
    All,
    Security,
}
