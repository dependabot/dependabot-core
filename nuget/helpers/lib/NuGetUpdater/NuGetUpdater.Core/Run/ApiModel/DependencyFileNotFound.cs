namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotFound : JobErrorBase
{
    public DependencyFileNotFound(string filePath, string? message = null)
        : base("dependency_file_not_found")
    {
        if (message is not null)
        {
            Details["message"] = message;
        }

        Details["file-path"] = filePath.NormalizePathToUnix();
    }
}
