namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotSupported : JobErrorBase
{
    public DependencyFileNotSupported(string dependencyName)
        : base("dependency_file_not_supported")
    {
        Details["dependency-name"] = dependencyName;
    }
}
