using System;
using System.IO;

namespace NuGetUpdater.Core.Test;

public sealed class TemporaryDirectory : IDisposable
{
    public string DirectoryPath { get; }

    public TemporaryDirectory()
    {
        var parentDir = Path.GetDirectoryName(GetType().Assembly.Location)!;
        var tempDirName = $"nuget-updater-{Guid.NewGuid():d}";
        DirectoryPath = Path.Combine(parentDir, "test-data", tempDirName);
        Directory.CreateDirectory(DirectoryPath);
    }

    public void Dispose()
    {
        Directory.Delete(DirectoryPath, true);
    }

    public static TemporaryDirectory CreateWithContents(params (string Path, string Contents)[] fileContents)
    {
        var temporaryDirectory = new TemporaryDirectory();
        foreach (var (path, contents) in fileContents)
        {
            var fullPath = Path.Combine(temporaryDirectory.DirectoryPath, path);
            var fullDirectory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(fullDirectory);
            File.WriteAllText(fullPath, contents);
        }

        return temporaryDirectory;
    }
}
