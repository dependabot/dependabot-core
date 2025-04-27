namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotParseable : JobErrorBase
{
    public DependencyFileNotParseable(string filePath, string? message = null)
        : base("dependency_file_not_parseable")
    {
        if (message is not null)
        {
            Details["message"] = message;
        }

        Details["file-path"] = filePath.NormalizePathToUnix();
    }
}
