namespace NuGetUpdater.Core;

internal class DependencyNotFoundException : Exception
{
    public string[] Dependencies { get; }

    public DependencyNotFoundException(string[] dependencies)
    {
        Dependencies = dependencies;
    }
}
