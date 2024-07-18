using System.Collections.Immutable;
using System.Text;

using NuGet.CommandLine;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

internal record NuGetContext : IDisposable
{
    public SourceCacheContext SourceCacheContext { get; }
    public PackageDownloadContext PackageDownloadContext { get; }
    public string CurrentDirectory { get; }
    public ISettings Settings { get; }
    public IMachineWideSettings MachineWideSettings { get; }
    public ImmutableArray<PackageSource> PackageSources { get; }
    public ILogger Logger { get; }
    public string TempPackageDirectory { get; }

    public NuGetContext(string? currentDirectory = null, ILogger? logger = null)
    {
        SourceCacheContext = new SourceCacheContext();
        PackageDownloadContext = new PackageDownloadContext(SourceCacheContext);
        CurrentDirectory = currentDirectory ?? Environment.CurrentDirectory;
        MachineWideSettings = new CommandLineMachineWideSettings();
        Settings = NuGet.Configuration.Settings.LoadDefaultSettings(
            CurrentDirectory,
            configFileName: null,
            MachineWideSettings);
        var sourceProvider = new PackageSourceProvider(Settings);
        PackageSources = sourceProvider.LoadPackageSources()
            .Where(p => p.IsEnabled)
            .ToImmutableArray();
        Logger = logger ?? NullLogger.Instance;
        TempPackageDirectory = Path.Combine(Path.GetTempPath(), $"dependabot-packages_{Guid.NewGuid():d}");
        Directory.CreateDirectory(TempPackageDirectory);
    }

    public void Dispose()
    {
        SourceCacheContext.Dispose();
        if (Directory.Exists(TempPackageDirectory))
        {
            try
            {
                Directory.Delete(TempPackageDirectory, recursive: true);
            }
            catch
            {
            }
        }
    }

    private readonly Dictionary<PackageIdentity, string?> _packageInfoUrlCache = new();

    public static string[] GetPackageSourceUrls(string currentDirectory)
    {
        using var context = new NuGetContext(currentDirectory);
        var sourceUrls = context.PackageSources.Select(s => s.Source).ToArray();
        return sourceUrls;
    }

    public async Task<string?> GetPackageInfoUrlAsync(string packageId, string packageVersion, CancellationToken cancellationToken)
    {
        var packageIdentity = new PackageIdentity(packageId, NuGetVersion.Parse(packageVersion));
        if (_packageInfoUrlCache.TryGetValue(packageIdentity, out var cachedUrl))
        {
            return cachedUrl;
        }

        var infoUrl = await FindPackageInfoUrlAsync(packageIdentity, cancellationToken);
        _packageInfoUrlCache[packageIdentity] = infoUrl;

        return infoUrl;
    }

    private async Task<string?> FindPackageInfoUrlAsync(PackageIdentity packageIdentity, CancellationToken cancellationToken)
    {
        var globalPackagesFolder = SettingsUtility.GetGlobalPackagesFolder(Settings);
        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(packageIdentity.Id).ToHashSet();
        var sources = packageSources.Count == 0
            ? PackageSources
            : PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        var message = new StringBuilder();
        message.AppendLine($"finding info url for {packageIdentity}, using package sources: {string.Join(", ", sources.Select(s => s.Name))}");

        foreach (var source in sources)
        {
            message.AppendLine($"  checking {source.Name}");
            var sourceRepository = Repository.Factory.GetCoreV3(source);
            var feed = await sourceRepository.GetResourceAsync<MetadataResource>(cancellationToken);
            if (feed is null)
            {
                message.AppendLine($"    feed for {source.Name} was null");
                continue;
            }

            try
            {
                // a non-compliant v2 API returning 404 can cause this to throw
                var existsInFeed = await feed.Exists(
                    packageIdentity,
                    includeUnlisted: false,
                    SourceCacheContext,
                    NullLogger.Instance,
                    cancellationToken);
                if (!existsInFeed)
                {
                    message.AppendLine($"    package {packageIdentity} does not exist in {source.Name}");
                    continue;
                }
            }
            catch (FatalProtocolException)
            {
                // if anything goes wrong here, the package source obviously doesn't contain the requested package
                continue;
            }

            var downloadResource = await sourceRepository.GetResourceAsync<DownloadResource>(cancellationToken);
            using var downloadResult = await downloadResource.GetDownloadResourceResultAsync(packageIdentity, PackageDownloadContext, globalPackagesFolder, Logger, cancellationToken);
            if (downloadResult.Status == DownloadResourceResultStatus.Available)
            {
                var repositoryMetadata = downloadResult.PackageReader.NuspecReader.GetRepositoryMetadata();
                message.AppendLine($"    repometadata: type=[{repositoryMetadata.Type}], url=[{repositoryMetadata.Url}], branch=[{repositoryMetadata.Branch}], commit=[{repositoryMetadata.Commit}]");
                if (!string.IsNullOrEmpty(repositoryMetadata.Url))
                {
                    return repositoryMetadata.Url;
                }
            }
            else
            {
                message.AppendLine($"    download result status: {downloadResult.Status}");
            }

            var metadataResource = await sourceRepository.GetResourceAsync<PackageMetadataResource>(cancellationToken);
            var metadata = await metadataResource.GetMetadataAsync(packageIdentity, SourceCacheContext, Logger, cancellationToken);
            var url = metadata.ProjectUrl ?? metadata.LicenseUrl;
            if (url is not null)
            {
                return url.ToString();
            }
        }

        return null;
    }
}
