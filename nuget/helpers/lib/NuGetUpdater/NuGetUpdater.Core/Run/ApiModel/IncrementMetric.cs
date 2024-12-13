namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record IncrementMetric
{
    public required string Metric { get; init; }
    public Dictionary<string, string> Tags { get; init; } = new();
}
