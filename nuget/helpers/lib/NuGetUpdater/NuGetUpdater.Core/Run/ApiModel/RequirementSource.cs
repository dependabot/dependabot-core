namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record RequirementSource
{
    public required string? SourceUrl { get; init; }
    public string Type { get; init; } = "nuget_repo";
}
