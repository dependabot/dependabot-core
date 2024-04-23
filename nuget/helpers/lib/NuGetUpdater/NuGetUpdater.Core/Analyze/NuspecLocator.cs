using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal static partial class NuspecLocator
{
    internal static readonly ImmutableArray<Regex> SupportedFeedRegexes = [
        // nuget
        NuGetOrgRegex(),
        // azure devops
        AzureArtifactsOrgProjectRegex(),
        AzureArtifactsOrgRegex(),
        VisualStudioRegex(),
    ];
    internal static readonly Dictionary<Uri, string?> BaseUrlCache = [];
    internal static readonly JsonSerializerOptions JsonSerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static async Task<string?> LocateNuspecAsync(
        string packageId,
        NuGetVersion version,
        NuGetContext nugetContext,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(nugetContext.Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(packageId).ToHashSet();
        var sources = packageSources.Count == 0
            ? nugetContext.PackageSources
            : nugetContext.PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        foreach (var source in sources)
        {
            var nuspecUrl = await LocateNuspecAsync(source, packageId, version, nugetContext, logger, cancellationToken);
            if (nuspecUrl is not null)
            {
                return nuspecUrl;
            }
        }

        return null;
    }

    public static async Task<string?> LocateNuspecAsync(
        PackageSource source,
        string packageId,
        NuGetVersion version,
        NuGetContext nugetContext,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var isSupported = DoesFeedSupportNuspecDownload(source);
        if (!isSupported)
        {
            return null;
        }

        var baseUrl = await GetBaseUrlAsync(source, nugetContext, cancellationToken);
        if (baseUrl is null)
        {
            return null;
        }

        var packageExists = await DoesPackageExistInFeedAsync(
            source,
            packageId,
            version,
            nugetContext,
            logger,
            cancellationToken);
        if (!packageExists)
        {
            return null;
        }

        return $"{baseUrl.TrimEnd('/')}/{packageId.ToLowerInvariant()}/{version.ToNormalizedString().ToLowerInvariant()}/{packageId.ToLowerInvariant()}.nuspec";
    }

    public static async Task<string?> GetBaseUrlAsync(
        PackageSource source,
        NuGetContext nugetContext,
        CancellationToken cancellationToken)
    {
        if (BaseUrlCache.TryGetValue(source.SourceUri, out var baseUrl))
        {
            return baseUrl;
        }

        var sourceRepository = Repository.Factory.GetCoreV3(source);
        var feed = await sourceRepository.GetResourceAsync<HttpSourceResource>();
        if (feed is null)
        {
            return null;
        }

        var httpSourceCacheContext = HttpSourceCacheContext.Create(nugetContext.SourceCacheContext, isFirstAttempt: true);
        var request = new HttpSourceCachedRequest(source.SourceUri.AbsoluteUri, "source_uri", httpSourceCacheContext);
        var result = await feed.HttpSource.GetAsync(
            request,
            async result =>
            {
                try
                {
                    return await GetV3BaseUrlAsync(result.Stream);
                }
                catch (JsonException)
                {
                    // V2 endpoint perhaps
                    return null;
                }
            },
            nugetContext.Logger,
            cancellationToken);

        BaseUrlCache[source.SourceUri] = result;

        return result;
    }

    internal static async Task<string?> GetV3BaseUrlAsync(Stream stream)
    {
        return (await JsonSerializer.DeserializeAsync<RepoMetadataResult>(stream, JsonSerializerOptions))
            ?.Resources
            .FirstOrDefault(r => r.Type == "PackageBaseAddress/3.0.0")
            ?.Id;
    }

    internal static bool DoesFeedSupportNuspecDownload(PackageSource source)
    {
        var feedUrl = source.SourceUri.AbsoluteUri;
        return SupportedFeedRegexes.Any(r => r.IsMatch(feedUrl));
    }

    internal static async Task<bool> DoesPackageExistInFeedAsync(
        PackageSource source,
        string packageId,
        NuGetVersion version,
        NuGetContext nugetContext,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var sourceRepository = Repository.Factory.GetCoreV3(source);
        var feed = await sourceRepository.GetResourceAsync<MetadataResource>();
        if (feed is null)
        {
            logger.Log($"Failed to get MetadataResource for [{source.Source}]");
            return false;
        }

        var existsInFeed = await feed.Exists(
            new PackageIdentity(packageId, version),
            includeUnlisted: false,
            nugetContext.SourceCacheContext,
            NullLogger.Instance,
            cancellationToken);

        return existsInFeed;
    }

    private class RepoMetadataResult
    {
        public required ResourceInfo[] Resources { get; set; }
    }

    private class ResourceInfo
    {
        [JsonPropertyName("@type")]
        public required string Type { get; set; }
        [JsonPropertyName("@id")]
        public required string Id { get; set; }
    }

    [GeneratedRegex(@"https://api\.nuget\.org/v3/index\.json")]
    private static partial Regex NuGetOrgRegex();
    [GeneratedRegex(@"https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/(?<project>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json")]
    private static partial Regex AzureArtifactsOrgProjectRegex();
    [GeneratedRegex(@"https://pkgs\.dev\.azure\.com/(?<organization>[^/]+)/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)")]
    private static partial Regex AzureArtifactsOrgRegex();
    [GeneratedRegex(@"https://(?<organization>[^\.\/]+)\.pkgs\.visualstudio\.com/_packaging/(?<feedId>[^/]+)/nuget/v3/index\.json(?<project>)")]
    private static partial Regex VisualStudioRegex();
}
