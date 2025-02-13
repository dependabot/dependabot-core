using System.Diagnostics.CodeAnalysis;

namespace NuGetUpdater.Core.Utilities;

public class PathComparer : IComparer<string>, IEqualityComparer<string>
{
    public static PathComparer Instance { get; } = new PathComparer();

    public int Compare(string? x, string? y)
    {
        x = x?.NormalizePathToUnix();
        y = y?.NormalizePathToUnix();

        if (x is null && y is null)
        {
            return 0;
        }

        if (x is null)
        {
            return -1;
        }

        if (y is null)
        {
            return 1;
        }

        return x.CompareTo(y);
    }

    public bool Equals(string? x, string? y) => Compare(x, y) == 0;

    public int GetHashCode([DisallowNull] string obj)
    {
        return obj.NormalizePathToUnix().GetHashCode();
    }
}
