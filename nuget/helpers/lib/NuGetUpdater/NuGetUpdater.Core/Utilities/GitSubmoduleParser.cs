using System.Collections.Immutable;

namespace NuGetUpdater.Core.Utilities;

internal static class GitSubmoduleParser
{
    /// <summary>
    /// Parses a .gitmodules file and returns the set of submodule paths relative to the repo root.
    /// </summary>
    public static ImmutableArray<string> GetSubmodulePaths(string repoRootPath)
    {
        var gitmodulesPath = Path.Combine(repoRootPath, ".gitmodules");
        if (!File.Exists(gitmodulesPath))
        {
            return [];
        }

        var content = File.ReadAllText(gitmodulesPath);
        return ParseSubmodulePaths(content);
    }

    /// <summary>
    /// Parses .gitmodules content and extracts the "path" values from each submodule section.
    /// </summary>
    internal static ImmutableArray<string> ParseSubmodulePaths(string content)
    {
        var paths = new List<string>();
        foreach (var line in content.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("path", StringComparison.OrdinalIgnoreCase) && trimmed.Contains('='))
            {
                var equalsIndex = trimmed.IndexOf('=');
                var pathValue = trimmed[(equalsIndex + 1)..].Trim();
                if (!string.IsNullOrEmpty(pathValue))
                {
                    paths.Add(pathValue.NormalizePathToUnix().NormalizeUnixPathParts().TrimEnd('/'));
                }
            }
        }

        return [.. paths];
    }

    /// <summary>
    /// Determines whether a given relative path (unix-style, relative to the repo root) falls under any submodule path.
    /// </summary>
    public static bool IsPathInSubmodule(string relativePath, ImmutableArray<string> submodulePaths)
    {
        var normalizedPath = relativePath.NormalizePathToUnix().NormalizeUnixPathParts().TrimEnd('/');
        foreach (var submodulePath in submodulePaths)
        {
            if (normalizedPath.Equals(submodulePath, StringComparison.OrdinalIgnoreCase) ||
                normalizedPath.StartsWith(submodulePath + "/", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
