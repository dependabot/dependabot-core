using System.Collections.Immutable;

using Newtonsoft.Json;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Analyze;

internal static class VersionFinder
{
    public static Task<VersionResult> GetVersionsByNameAsync(
        ImmutableArray<NuGetFramework> projectTfms,
        string dependencyName,
        NuGetVersion currentVersion,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken
    )
    {
        var dependencyInfo = new DependencyInfo()
        {
            Name = dependencyName,
            Version = currentVersion.ToString(),
            IsVulnerable = false,
        };
        return GetVersionsAsync(
            projectTfms,
            dependencyInfo,
            currentVersion,
            DateTime.UtcNow,
            nugetContext,
            logger,
            cancellationToken
        );
    }

    public static Task<VersionResult> GetVersionsAsync(
        ImmutableArray<NuGetFramework> projectTfms,
        DependencyInfo dependencyInfo,
        NuGetVersion currentVersion,
        DateTimeOffset currentTime,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versionFilter = CreateVersionFilter(currentVersion);

        return GetVersionsAsync(projectTfms, dependencyInfo, currentVersion, versionFilter, currentTime, nugetContext, logger, cancellationToken);
    }

    public static Task<VersionResult> GetVersionsAsync(
        ImmutableArray<NuGetFramework> projectTfms,
        DependencyInfo dependencyInfo,
        DateTimeOffset currentTime,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versionRange = VersionRange.Parse(dependencyInfo.Version);
        var currentVersion = versionRange.MinVersion!;
        var versionFilter = CreateVersionFilter(dependencyInfo, versionRange);

        return GetVersionsAsync(projectTfms, dependencyInfo, currentVersion, versionFilter, currentTime, nugetContext, logger, cancellationToken);
    }

    public static async Task<VersionResult> GetVersionsAsync(
        ImmutableArray<NuGetFramework> projectTfms,
        DependencyInfo dependencyInfo,
        NuGetVersion currentVersion,
        Func<NuGetVersion, bool> versionFilter,
        DateTimeOffset currentTime,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var includePrerelease = currentVersion.IsPrerelease;
        VersionResult result = new(currentVersion);

        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(nugetContext.Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(dependencyInfo.Name).ToHashSet();
        var sources = packageSources.Count == 0
            ? nugetContext.PackageSources
            : nugetContext.PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        foreach (var source in sources)
        {
            MetadataResource? feed = null;
            PackageMetadataResource? metadataResource = null;
            try
            {
                var sourceRepository = Repository.Factory.GetCoreV3(source);
                feed = await sourceRepository.GetResourceAsync<MetadataResource>();
                if (feed is null)
                {
                    logger.Warn($"Failed to get {nameof(MetadataResource)} for [{source.Source}]");
                    continue;
                }

                var packageFinder = await sourceRepository.GetResourceAsync<FindPackageByIdResource>();
                if (packageFinder is null)
                {
                    logger.Warn($"Failed to get {nameof(FindPackageByIdResource)} for [{source.Source}]");
                    continue;
                }

                if (dependencyInfo.Cooldown is not null)
                {
                    metadataResource = await sourceRepository.GetResourceAsync<PackageMetadataResource>();
                    if (metadataResource is null)
                    {
                        logger.Warn($"Failed to get {nameof(PackageMetadataResource)} for [{source.Source}]");
                        continue;
                    }
                }

                // a non-compliant v2 API returning 404 can cause this to throw
                var existsInFeed = await feed.Exists(
                    dependencyInfo.Name,
                    includePrerelease,
                    includeUnlisted: false,
                    nugetContext.SourceCacheContext,
                    NullLogger.Instance,
                    cancellationToken);
                if (!existsInFeed)
                {
                    continue;
                }
            }
            catch (FatalProtocolException)
            {
                // if anything goes wrong here, the package source obviously doesn't contain the requested package
                continue;
            }
            catch (JsonReaderException ex)
            {
                // unable to parse server response
                throw new BadResponseException(ex.Message, source.Source);
            }

            var feedVersions = (await feed.GetVersions(
                dependencyInfo.Name,
                includePrerelease,
                includeUnlisted: false,
                nugetContext.SourceCacheContext,
                NullLogger.Instance,
                CancellationToken.None)).ToHashSet();

            if (feedVersions.Contains(currentVersion))
            {
                result.AddCurrentVersionSource(source);
            }

            var versions = feedVersions.Where(versionFilter).ToArray();
            foreach (var version in versions)
            {
                var packageIdentity = new PackageIdentity(dependencyInfo.Name, version);

                // check tfm
                var isTfmCompatible = await CompatibilityChecker.CheckAsync(
                    packageIdentity,
                    projectTfms,
                    nugetContext,
                    logger,
                    CancellationToken.None);

                // dotnet-tools.json and global.json packages won't specify a TFM, so they're always compatible
                if (isTfmCompatible || projectTfms.IsEmpty)
                {
                    // check date
                    if (dependencyInfo.Cooldown is not null)
                    {
                        var metadata = await metadataResource!.GetMetadataAsync(packageIdentity, nugetContext.SourceCacheContext, NullLogger.Instance, CancellationToken.None);
                        if (!dependencyInfo.Cooldown.IsVersionUpdateAllowed(currentTime, metadata?.Published, currentVersion, version))
                        {
                            logger.Info($"Skipping update of {dependencyInfo.Name} from {currentVersion} to {version} due to cooldown settings.  Package publish date: {metadata?.Published}");
                            continue;
                        }
                    }

                    result.Add(source, version);
                }
            }
        }

        return result;
    }

    internal static Func<NuGetVersion, bool> CreateVersionFilter(DependencyInfo dependencyInfo, VersionRange versionRange)
    {
        // If we are floating to the absolute latest version, we should not filter pre-release versions at all.
        var currentVersion = versionRange.Float?.FloatBehavior != NuGetVersionFloatBehavior.AbsoluteLatest
            ? versionRange.MinVersion
            : null;

        var safeVersions = dependencyInfo.Vulnerabilities.SelectMany(v => v.SafeVersions).ToList();
        return version =>
        {
            var versionGreaterThanCurrent = currentVersion is null || version > currentVersion;
            var rangeSatisfies = versionRange.Satisfies(version);
            var prereleaseTypeMatches = currentVersion is null || !currentVersion.IsPrerelease || !version.IsPrerelease || version.Version == currentVersion.Version;
            var isIgnoredVersion = dependencyInfo.IgnoredVersions.Any(i => i.IsSatisfiedBy(version));
            var isVulnerableVersion = dependencyInfo.Vulnerabilities.Any(v => v.IsVulnerable(version));
            var isSafeVersion = !safeVersions.Any() || safeVersions.Any(s => s.IsSatisfiedBy(version));

            var isIgnoredByType = false;
            if (currentVersion is not null)
            {
                var isMajorBump = version.Major > currentVersion.Major;
                var isMinorBump = version.Major == currentVersion.Major && version.Minor > currentVersion.Minor;
                var isPatchBump = version.Major == currentVersion.Major && version.Minor == currentVersion.Minor && version.Patch > currentVersion.Patch;
                foreach (var ignoreType in dependencyInfo.IgnoredUpdateTypes)
                {
                    switch (ignoreType)
                    {
                        case ConditionUpdateType.SemVerPatch:
                            isIgnoredByType = isIgnoredByType || isPatchBump || isMinorBump || isMajorBump;
                            break;
                        case ConditionUpdateType.SemVerMinor:
                            isIgnoredByType = isIgnoredByType || isMinorBump || isMajorBump;
                            break;
                        case ConditionUpdateType.SemVerMajor:
                            isIgnoredByType = isIgnoredByType || isMajorBump;
                            break;
                        default:
                            break;
                    }
                }
            }

            return versionGreaterThanCurrent
                && rangeSatisfies
                && prereleaseTypeMatches
                && !isIgnoredVersion
                && !isVulnerableVersion
                && isSafeVersion
                && !isIgnoredByType;
        };
    }

    internal static Func<NuGetVersion, bool> CreateVersionFilter(NuGetVersion currentVersion)
    {
        return version => version > currentVersion
            && (currentVersion is null || !currentVersion.IsPrerelease || !version.IsPrerelease || version.Version == currentVersion.Version);
    }

    public static async Task<bool> DoVersionsExistAsync(
        IEnumerable<string> packageIds,
        NuGetVersion version,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        foreach (var packageId in packageIds)
        {
            if (!await DoesVersionExistAsync(packageId, version, nugetContext, logger, cancellationToken))
            {
                return false;
            }
        }

        return true;
    }

    public static async Task<bool> DoesVersionExistAsync(
        string packageId,
        NuGetVersion version,
        NuGetContext nugetContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        // if it can be downloaded, it exists
        var downloader = await CompatibilityChecker.DownloadPackageAsync(new PackageIdentity(packageId, version), nugetContext, cancellationToken);
        var packageAndVersionExists = downloader is not null;
        if (packageAndVersionExists)
        {
            // release the handles
            var readers = downloader.GetValueOrDefault();
            (readers.CoreReader as IDisposable)?.Dispose();
            (readers.ContentReader as IDisposable)?.Dispose();
        }

        return packageAndVersionExists;
    }
}
