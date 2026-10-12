namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record ReportedDependencyWithDirectory : ReportedDependency
{
    public required string Directory { get; init; }

    public static ReportedDependencyWithDirectory From(ReportedDependency dependency, string directory)
    {
        return new ReportedDependencyWithDirectory()
        {
            Name = dependency.Name,
            Version = dependency.Version,
            Requirements = dependency.Requirements,
            PreviousVersion = dependency.PreviousVersion,
            PreviousRequirements = dependency.PreviousRequirements,
            Directory = directory,
        };
    }
}
