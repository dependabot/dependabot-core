namespace NuGetUpdater.Core.Test;

using TestFile = (string Path, string Contents);

public sealed class TemporaryDirectory : IDisposable
{
    private readonly TemporaryEnvironment _environment;
    private readonly string _rootDirectory;

    public string DirectoryPath { get; }

    public TemporaryDirectory()
    {
        var parentDir = Path.GetDirectoryName(GetType().Assembly.Location)!;
        var tempDirName = $"nuget-updater-{Guid.NewGuid():d}";
        _rootDirectory = Path.Combine(parentDir, "test-data", tempDirName);
        _environment = new TemporaryEnvironment(
            [
                ("NUGET_PACKAGES", Path.Combine(_rootDirectory, "NUGET_PACKAGES")),
                ("NUGET_HTTP_CACHE_PATH", Path.Combine(_rootDirectory, "NUGET_HTTP_CACHE_PATH")),
                ("NUGET_SCRATCH", Path.Combine(_rootDirectory, "NUGET_SCRATCH")),
                ("NUGET_PLUGINS_CACHE_PATH", Path.Combine(_rootDirectory, "NUGET_PLUGINS_CACHE_PATH")),
            ]);

        DirectoryPath = Path.Combine(_rootDirectory, "repo-root");
        Directory.CreateDirectory(DirectoryPath);
    }

    public void Dispose()
    {
        _environment.Dispose();
        Directory.Delete(_rootDirectory, true);
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

        // prevent directory crawling
        await File.WriteAllTextAsync(Path.Combine(temporaryDirectory._rootDirectory, "Directory.Build.props"), "<Project />");
        await File.WriteAllTextAsync(Path.Combine(temporaryDirectory._rootDirectory, "Directory.Build.targets"), "<Project />");
        await File.WriteAllTextAsync(Path.Combine(temporaryDirectory._rootDirectory, "Directory.Packages.props"), """
            <Project>
              <PropertyGroup>
                <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
              </PropertyGroup>
            </Project>
            """);

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
