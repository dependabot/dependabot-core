namespace NuGetUpdater.Core;

public sealed class DependencyRequest
{
    public string Name { get; set; } = null!;

    public string NewVersion { get; set; } = null!;

    public string PreviousVersion { get; set; } = null!;

    public bool IsTransitive { get; set; } = false;
}
