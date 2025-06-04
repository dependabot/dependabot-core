namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyNotFound : JobErrorBase
{
    public DependencyNotFound(string dependency)
        : base("dependency_not_found")
    {
        // the corresponding error type in Ruby calls this `source` but it's treated like a dependency name
        Details["source"] = dependency;
    }
}
