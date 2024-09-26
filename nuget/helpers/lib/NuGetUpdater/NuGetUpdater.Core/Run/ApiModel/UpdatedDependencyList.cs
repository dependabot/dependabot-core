namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record UpdatedDependencyList
{
    public required ReportedDependency[] Dependencies { get; init; }
    public required string[] DependencyFiles { get; init; }
}
