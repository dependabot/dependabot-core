namespace NuGetUpdater.Core;

internal class UpdateNotPossibleException : Exception
{
    public string[] Dependencies { get; }

    public UpdateNotPossibleException(string[] dependencies)
    {
        Dependencies = dependencies;
    }
}
