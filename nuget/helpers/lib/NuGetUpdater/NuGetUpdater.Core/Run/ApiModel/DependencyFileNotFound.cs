namespace NuGetUpdater.Core.Run.ApiModel;

public record DependencyFileNotFound : JobErrorBase
{
    public override string Type => "dependency_file_not_found";
}
