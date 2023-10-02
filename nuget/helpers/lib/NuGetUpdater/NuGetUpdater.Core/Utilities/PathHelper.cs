using System.IO;

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

    public static string GetFullPathFromRelative(string rootPath, string relativePath)
        => Path.GetFullPath(JoinPath(rootPath, relativePath.Replace("\\", "/")));
}