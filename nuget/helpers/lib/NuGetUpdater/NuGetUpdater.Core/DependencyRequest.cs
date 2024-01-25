namespace NuGetUpdater.Core;

public class DependencyRequest
{
    public string Name { get; set; } = null!;

    public string NewVersion { get; set; } = null!;

    public string PreviousVersion { get; set; } = null!;

    public bool IsTransitive { get; set; } = false;
}
