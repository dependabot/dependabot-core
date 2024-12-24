namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotFound : JobErrorBase
{
    public DependencyFileNotFound(string message, string filePath)
        : base("dependency_file_not_found")
    {
        Details["message"] = message;
        Details["file-path"] = filePath;
    }
}
