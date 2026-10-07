namespace NuGetUpdater.Core.Run.ApiModel;

public record OutOfDisk : JobErrorBase
{
    public OutOfDisk()
        : base("out_of_disk")
    {
    }
}
