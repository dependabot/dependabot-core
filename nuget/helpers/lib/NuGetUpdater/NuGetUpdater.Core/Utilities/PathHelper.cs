using System.Collections.Generic;
using System.IO;
using System.Linq;

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

    public static string NormalizePathToUnix(this string path) => path.Replace("\\", "/");

    public static string GetFullPathFromRelative(string rootPath, string relativePath)
        => Path.GetFullPath(JoinPath(rootPath, relativePath.NormalizePathToUnix()));

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

        var candidatePaths = new List<string>();
        var rootDirectory = new DirectoryInfo(rootPath);
        var candidateDirectory = new DirectoryInfo(initialPath);
        while (candidateDirectory.FullName != rootDirectory.FullName)
        {
            candidatePaths.Add(candidateDirectory.FullName);
            candidateDirectory = candidateDirectory.Parent;
            if (candidateDirectory is null)
            {
                break;
            }
        }

        candidatePaths.Add(rootPath);

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
}
