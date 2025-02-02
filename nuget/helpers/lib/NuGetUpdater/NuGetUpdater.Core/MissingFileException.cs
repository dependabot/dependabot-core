namespace NuGetUpdater.Core;

internal class MissingFileException : Exception
{
    public string FilePath { get; }

    public MissingFileException(string filePath, string? message = null)
        : base(message)
    {
        FilePath = filePath;
    }
}
