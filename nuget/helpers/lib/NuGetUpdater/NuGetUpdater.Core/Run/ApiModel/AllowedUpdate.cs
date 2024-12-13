namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record AllowedUpdate
{
    public DependencyType DependencyType { get; init; } = DependencyType.All;
    public string? DependencyName { get; init; } = null;
    public UpdateType UpdateType { get; init; } = UpdateType.All;
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
