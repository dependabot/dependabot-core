namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotFound : JobErrorBase
{
    public DependencyFileNotFound(string filePath)
        : base("dependency_file_not_found")
    {
        Details = filePath;
    }
}
