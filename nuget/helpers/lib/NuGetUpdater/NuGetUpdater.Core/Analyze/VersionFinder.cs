using System.Collections.Immutable;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;

using NuGetUpdater.Core;

namespace NuGetUpdater.Analyzer;

internal static class VersionFinder
{
    public static async Task<VersionResult> GetVersionsAsync(
        string packageId,
        bool includePrerelease,
        NuGetContext context,
        Logger logger,
        CancellationToken cancellationToken)
    {
        VersionResult result = new();

        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(context.Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(packageId).ToHashSet();
        var sources = packageSources.Count == 0
            ? context.PackageSources
            : context.PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        foreach (var source in sources)
        {
            var sourceRepository = Repository.Factory.GetCoreV3(source);
            var feed = await sourceRepository.GetResourceAsync<MetadataResource>();
            if (feed is null)
            {
                // $"Failed to get MetadataResource for {source.SourceUri}"
                continue;
            }

            var existsInFeed = await feed.Exists(
                packageId,
                includePrerelease,
                includeUnlisted: false,
                context.SourceCacheContext,
                NullLogger.Instance,
                cancellationToken);
            if (!existsInFeed)
            {
                continue;
            }

            var feedVersions = await feed.GetVersions(
                packageId,
                includePrerelease,
                includeUnlisted: false,
                context.SourceCacheContext,
                NullLogger.Instance,
                CancellationToken.None);

            result.AddRange(source, feedVersions);
        }

        return result;
    }
}
