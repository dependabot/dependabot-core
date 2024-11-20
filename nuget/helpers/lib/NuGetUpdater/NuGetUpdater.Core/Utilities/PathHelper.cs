using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace NuGetUpdater.Core;

internal static class PathHelper
{
    private static readonly EnumerationOptions _caseInsensitiveEnumerationOptions = new()
    {
        MatchCasing = MatchCasing.CaseInsensitive,
    };

    private static readonly EnumerationOptions _caseSensitiveEnumerationOptions = new()
    {
        MatchCasing = MatchCasing.CaseSensitive,
    };

    public static string JoinPath(string? path1, string path2)
    {
        // don't root out the second path
        if (path2.StartsWith('/'))
        {
            path2 = path2[1..];
        }

        return path1 is null
            ? path2
            : Path.Combine(path1, path2);
    }

    public static string EnsurePrefix(this string s, string prefix) => s.StartsWith(prefix) ? s : prefix + s;

    public static string EnsureSuffix(this string s, string suffix) => s.EndsWith(suffix) ? s : s + suffix;

    public static string NormalizePathToUnix(this string path) => path.Replace("\\", "/");

    public static string NormalizeUnixPathParts(this string path)
    {
        var parts = path.Split('/');
        var resultantParts = new List<string>();
        foreach (var part in parts)
        {
            switch (part)
            {
                case "":
                case ".":
                    break;
                case "..":
                    if (resultantParts.Count > 0)
                    {
                        resultantParts.RemoveAt(resultantParts.Count - 1);
                    }
                    break;
                default:
                    resultantParts.Add(part);
                    break;
            }
        }

        var result = string.Join("/", resultantParts);
        if (path.StartsWith("/") && !result.StartsWith("/"))
        {
            result = "/" + result;
        }

        return result;
    }

    public static string FullyNormalizedRootedPath(this string path)
    {
        var normalizedPath = path.NormalizePathToUnix().NormalizeUnixPathParts();
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && Regex.IsMatch(normalizedPath, @"^[a-z]:", RegexOptions.IgnoreCase))
        {
            // Windows path is ready to go
            return normalizedPath;
        }

        return normalizedPath.EnsurePrefix("/");
    }

    public static string GetFullPathFromRelative(string rootPath, string relativePath)
        => Path.GetFullPath(JoinPath(rootPath, relativePath.NormalizePathToUnix()));

    public static string[] GetAllDirectoriesToRoot(string initialDirectoryPath, string rootDirectoryPath)
    {
        var candidatePaths = new List<string>();
        var rootDirectory = new DirectoryInfo(rootDirectoryPath);
        var candidateDirectory = new DirectoryInfo(initialDirectoryPath);
        while (candidateDirectory.FullName != rootDirectory.FullName)
        {
            candidatePaths.Add(candidateDirectory.FullName);
            candidateDirectory = candidateDirectory.Parent;
            if (candidateDirectory is null)
            {
                break;
            }
        }

        candidatePaths.Add(rootDirectoryPath);
        return candidatePaths.ToArray();
    }

    /// <summary>
    /// Resolves the case of the file path in a case-insensitive manner. Returns null if the file path is not found. file path must be a full path inside the repoRootPath.
    /// </summary>
    /// <param name="filePath">The file path to resolve.</param>
    /// <param name="repoRootPath">The root path of the repository.</param>
    public static string? ResolveCaseInsensitivePathInsideRepoRoot(string filePath, string repoRootPath)
    {
        if (string.IsNullOrEmpty(filePath) || string.IsNullOrEmpty(repoRootPath))
        {
            return null; // Invalid input
        }

        // Normalize paths
        var normalizedFilePath = filePath.FullyNormalizedRootedPath();
        var normalizedRepoRoot = repoRootPath.FullyNormalizedRootedPath();

        // Ensure the file path starts with the repo root path
        if (!normalizedFilePath.StartsWith(normalizedRepoRoot + "/", StringComparison.OrdinalIgnoreCase))
        {
            return null; // filePath is outside of repoRootPath
        }

        // Start resolving from the root path
        var currentPath = normalizedRepoRoot;
        var relativePath = normalizedFilePath.Substring(normalizedRepoRoot.Length).TrimStart('/');

        foreach (var part in relativePath.Split('/'))
        {
            if (string.IsNullOrEmpty(part))
            {
                continue;
            }

            // Enumerate the current directory to find a case-insensitive match
            var nextPath = Directory
                .EnumerateFileSystemEntries(currentPath)
                .FirstOrDefault(entry => string.Equals(Path.GetFileName(entry), part, StringComparison.OrdinalIgnoreCase));

            if (nextPath == null)
            {
                return null; // Part of the path does not exist
            }

            currentPath = nextPath;
        }

        return currentPath.NormalizePathToUnix(); // Fully resolved path with correct casing
    }

    /// <summary>
    /// Check in every directory from <paramref name="initialPath"/> up to <paramref name="rootPath"/> for the file specified in <paramref name="fileName"/>.
    /// </summary>
    /// <returns>The path of the found file or null.</returns>
    public static string? GetFileInDirectoryOrParent(string initialPath, string rootPath, string fileName, bool caseSensitive = true)
    {
        if (File.Exists(initialPath))
        {
            initialPath = Path.GetDirectoryName(initialPath)!;
        }

        var candidatePaths = GetAllDirectoriesToRoot(initialPath, rootPath);
        foreach (var candidatePath in candidatePaths)
        {
            try
            {
                var files = Directory.EnumerateFiles(candidatePath, fileName, caseSensitive ? _caseSensitiveEnumerationOptions : _caseInsensitiveEnumerationOptions);

                if (files.Any())
                {
                    return files.First();
                }
            }
            catch (DirectoryNotFoundException)
            {
                // When searching for a file in a directory that doesn't exist, Directory.EnumerateFiles throws a DirectoryNotFoundException.
            }
        }

        return null;
    }

    public static void CopyDirectory(string sourceDirectory, string destinationDirectory)
    {
        var sourceDirInfo = new DirectoryInfo(sourceDirectory);
        var destinationDirInfo = new DirectoryInfo(destinationDirectory);

        if (!sourceDirInfo.Exists)
        {
            throw new DirectoryNotFoundException($"Source directory does not exist or could not be found: {sourceDirectory}");
        }

        if (!destinationDirInfo.Exists)
        {
            destinationDirInfo.Create();
        }

        foreach (var file in sourceDirInfo.EnumerateFiles())
        {
            file.CopyTo(Path.Combine(destinationDirectory, file.Name), true);
        }

        foreach (var subDir in sourceDirInfo.EnumerateDirectories())
        {
            var newDestinationDir = Path.Combine(destinationDirectory, subDir.Name);
            CopyDirectory(subDir.FullName, newDestinationDir);
        }
    }

    public static bool IsSubdirectoryOf(string parentDirectory, string childDirectory)
    {
        var parentDirInfo = new DirectoryInfo(parentDirectory);
        var childDirInfo = new DirectoryInfo(childDirectory);

        while (childDirInfo.Parent is not null)
        {
            if (childDirInfo.Parent.FullName == parentDirInfo.FullName)
            {
                return true;
            }

            childDirInfo = childDirInfo.Parent;
        }

        return false;
    }

    public static bool IsFileUnderDirectory(DirectoryInfo directory, FileInfo candidateFile)
    {
        // n.b., using `DirectoryInfo` and `FileInfo` here to ensure that the callsite doesn't get confused with just strings
        // the paths are then normalized to make the comparison easier.
        var directoryPath = directory.FullName.NormalizePathToUnix();
        if (!directoryPath.EndsWith("/"))
        {
            // ensuring a trailing slash means we can do a simple string check later on
            directoryPath += "/";
        }
        var candidateFilePath = candidateFile.FullName.NormalizePathToUnix();

        return candidateFilePath.StartsWith(directoryPath);
    }
}
