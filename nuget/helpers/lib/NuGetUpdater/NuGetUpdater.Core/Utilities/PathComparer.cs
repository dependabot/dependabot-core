using System.Diagnostics.CodeAnalysis;

namespace NuGetUpdater.Core.Utilities;

public class PathComparer : IEqualityComparer<string>
{
    public static PathComparer Instance { get; } = new PathComparer();

    public bool Equals(string? x, string? y)
    {
        x = x?.NormalizePathToUnix();
        y = y?.NormalizePathToUnix();

        if (x is null && y is null)
        {
            return true;
        }

        if (x is null || y is null)
        {
            return false;
        }

        return x.Equals(y, StringComparison.OrdinalIgnoreCase);
    }

    public int GetHashCode([DisallowNull] string obj)
    {
        return obj.NormalizePathToUnix().GetHashCode();
    }
}
