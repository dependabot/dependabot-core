namespace NuGetUpdater.Core.Test;

using TestFile = (string Path, string Contents);

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

    public async Task<TestFile[]> ReadFileContentsAsync(HashSet<string> filePaths)
    {
        var files = new List<(string Path, string Content)>();
        foreach (var file in Directory.GetFiles(DirectoryPath, "*.*", SearchOption.AllDirectories))
        {
            var localPath = file.StartsWith(DirectoryPath)
                ? file[DirectoryPath.Length..]
                : file; // how did this happen?
            localPath = localPath.NormalizePathToUnix();
            if (localPath.StartsWith('/'))
            {
                localPath = localPath[1..];
            }

            if (filePaths.Contains(localPath))
            {
                var content = await File.ReadAllTextAsync(file);
                files.Add((localPath, content));
            }
        }

        return files.ToArray();
    }

    public static async Task<TemporaryDirectory> CreateWithContentsAsync(params TestFile[] fileContents)
    {
        var temporaryDirectory = new TemporaryDirectory();

        var parentDirectory = Path.GetDirectoryName(temporaryDirectory.DirectoryPath)!;

        // prevent directory crawling
        await File.WriteAllTextAsync(Path.Combine(parentDirectory, "Directory.Build.props"), """
            <Project>
              <PropertyGroup>
                <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
              </PropertyGroup>
            </Project>
            """);
        await File.WriteAllTextAsync(Path.Combine(parentDirectory, "Directory.Build.targets"), "<Project />");

        foreach (var (path, contents) in fileContents)
        {
            var localPath = path.StartsWith('/') ? path[1..] : path; // remove path rooting character
            var fullPath = Path.Combine(temporaryDirectory.DirectoryPath, localPath);
            var fullDirectory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(fullDirectory);
            await File.WriteAllTextAsync(fullPath, contents);
        }

        return temporaryDirectory;
    }
}
