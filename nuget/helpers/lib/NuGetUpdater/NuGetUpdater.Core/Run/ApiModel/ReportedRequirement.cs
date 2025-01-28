namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record ReportedRequirement
{
    public required string Requirement { get; init; }
    public required string File { get; init; }
    public string[] Groups { get; init; } = Array.Empty<string>();
    public RequirementSource? Source { get; init; } = null;
}
