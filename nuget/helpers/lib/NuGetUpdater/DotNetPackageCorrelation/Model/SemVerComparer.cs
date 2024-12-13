using Semver;

namespace DotNetPackageCorrelation;

public class SemVerComparer : IComparer<SemVersion>
{
    public static SemVerComparer Instance = new();

    public int Compare(SemVersion? x, SemVersion? y)
    {
        ArgumentNullException.ThrowIfNull(x);
        ArgumentNullException.ThrowIfNull(y);

        return x.ComparePrecedenceTo(y);
    }
}
