using System;
using System.IO;

namespace NuGetUpdater.Core.Test;

public class TemporaryDirectory : IDisposable
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
}