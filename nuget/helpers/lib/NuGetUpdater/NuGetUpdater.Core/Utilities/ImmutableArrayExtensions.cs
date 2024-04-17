using System.Collections.Immutable;

namespace NuGetUpdater.Core.Utilities;

public static class ImmutableArrayExtensions
{
    public static bool SequenceEqual<T>(this ImmutableArray<T>? expected, ImmutableArray<T>? actual, IEqualityComparer<T>? equalityComparer = null)
    {
        if (expected is null)
        {
            return actual is null;
        }
        else
        {
            return actual is not null && expected.Value.SequenceEqual(actual.Value, equalityComparer);
        }
    }
}
