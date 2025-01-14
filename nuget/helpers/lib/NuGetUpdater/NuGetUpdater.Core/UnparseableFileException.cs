namespace NuGetUpdater.Core;

internal class UnparseableFileException : Exception
{
    public string FilePath { get; }

    public UnparseableFileException(string message, string filePath)
        : base(message)
    {
        FilePath = filePath;
    }
}
