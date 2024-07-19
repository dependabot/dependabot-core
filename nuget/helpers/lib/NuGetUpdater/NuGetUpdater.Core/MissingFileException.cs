namespace NuGetUpdater.Core;

internal class MissingFileException : Exception
{
    public string FilePath { get; }

    public MissingFileException(string filePath)
    {
        FilePath = filePath;
    }
}
