namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyGroup
{
    public required string Name { get; init; }
    public string? AppliesTo { get; init; }
    public Dictionary<string, object> Rules { get; init; } = new();
}
