using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace NuGetUpdater.Core;

internal static class PathHelper
{
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
    public static string? GetFileInDirectoryOrParent(string initialPath, string rootPath, string fileName)
    {
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
        var candidateFilePaths = candidatePaths.Select(p => Path.Combine(p, fileName)).ToList();
        return candidateFilePaths.FirstOrDefault(File.Exists);
    }
}
