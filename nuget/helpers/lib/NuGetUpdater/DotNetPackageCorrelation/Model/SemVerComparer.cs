using Semver;

namespace DotNetPackageCorrelation;

public class SemVerComparer : IComparer<SemVersion>
{
    public int Compare(SemVersion? x, SemVersion? y)
    {
        ArgumentNullException.ThrowIfNull(x);
        ArgumentNullException.ThrowIfNull(y);

        return x.CompareSortOrderTo(y);
    }
}
