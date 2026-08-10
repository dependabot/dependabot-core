using NuGet.LibraryModel;

namespace NuGetUpdater.Core;

internal static class DependencyAssetFlags
{
    private const LibraryIncludeFlags CompatibilityAssets =
        LibraryIncludeFlags.Compile | LibraryIncludeFlags.Runtime;

    public static LibraryIncludeFlags GetAssetFlags(this Dependency dependency, string targetFramework)
    {
        return dependency.AssetFlags?.GetValueOrDefault(targetFramework, LibraryIncludeFlags.All)
            ?? LibraryIncludeFlags.All;
    }

    public static bool RequiresCompatibilityCheck(this Dependency dependency, string targetFramework)
    {
        return (dependency.GetAssetFlags(targetFramework) & CompatibilityAssets) != LibraryIncludeFlags.None;
    }

    public static string? GetIncludeAssetsValue(this Dependency dependency, string targetFramework)
    {
        var flags = dependency.GetAssetFlags(targetFramework);
        return flags == LibraryIncludeFlags.All
            ? null
            : LibraryIncludeFlagUtils.GetFlagString(flags).Replace(", ", ";", StringComparison.Ordinal);
    }
}
