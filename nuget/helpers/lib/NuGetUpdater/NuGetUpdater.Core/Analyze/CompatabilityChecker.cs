using System.Collections.Immutable;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;

using NuGetUpdater.Core.FrameworkChecker;

namespace NuGetUpdater.Core.Analyze;

using PackageInfo = (bool IsDevDependency, ImmutableArray<NuGetFramework> Frameworks);
using PackageReaders = (IAsyncPackageCoreReader CoreReader, IAsyncPackageContentReader ContentReader);

internal static class CompatibilityChecker
{
    public static async Task<bool> CheckAsync(
        PackageIdentity package,
        ImmutableArray<NuGetFramework> projectFrameworks,
        NuGetContext nugetContext,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var (isDevDependency, packageFrameworks) = await GetPackageInfoAsync(
            package,
            nugetContext,
            cancellationToken);

        return PerformCheck(package, projectFrameworks, isDevDependency, packageFrameworks, logger);
    }

    internal static bool PerformCheck(
        PackageIdentity package,
        ImmutableArray<NuGetFramework> projectFrameworks,
        bool isDevDependency,
        ImmutableArray<NuGetFramework> packageFrameworks,
        Logger logger)
    {
        // development dependencies are packages such as analyzers which need to be compatible with the compiler not the
        // project itself, but some packages that report themselves as development dependencies still contain target
        // framework dependencies and should be checked for compatibility through the regular means
        if (isDevDependency && packageFrameworks.Length == 0)
        {
            return true;
        }

        if (packageFrameworks.Length == 0 || projectFrameworks.Length == 0)
        {
            return false;
        }

        var compatibilityService = new FrameworkCompatibilityService();
        var compatibleFrameworks = compatibilityService.GetCompatibleFrameworks(packageFrameworks);
        var packageSupportsAny = compatibleFrameworks.Any(f => f.IsAny);
        if (packageSupportsAny)
        {
            return true;
        }

        var incompatibleFrameworks = projectFrameworks.Where(f => !compatibleFrameworks.Contains(f)).ToArray();
        if (incompatibleFrameworks.Length > 0)
        {
            logger.Log($"The package {package} is not compatible. Incompatible project frameworks: {string.Join(", ", incompatibleFrameworks.Select(f => f.GetShortFolderName()))}");
            return false;
        }

        return true;
    }

    internal static async Task<PackageInfo> GetPackageInfoAsync(
        PackageIdentity package,
        NuGetContext nugetContext,
        CancellationToken cancellationToken)
    {
        var tempPackagePath = GetTempPackagePath(package, nugetContext);
        var readers = File.Exists(tempPackagePath)
            ? ReadPackage(tempPackagePath)
            : await DownloadPackageAsync(package, nugetContext, cancellationToken);

        var nuspecStream = await readers.CoreReader.GetNuspecAsync(cancellationToken);
        var reader = new NuspecReader(nuspecStream);

        var isDevDependency = reader.GetDevelopmentDependency();
        var tfms = new HashSet<NuGetFramework>();
        var dependencyGroups = reader.GetDependencyGroups().ToArray();

        foreach (var d in dependencyGroups)
        {
            var libItems = (await readers.ContentReader.GetLibItemsAsync(cancellationToken)).ToList();

            foreach (var item in libItems)
            {
                tfms.Add(item.TargetFramework);
            }

            if (!d.TargetFramework.IsAny)
            {
                tfms.Add(d.TargetFramework);
            }
        }

        if (!tfms.Any())
        {
            tfms.Add(NuGetFramework.AnyFramework);
        }

        // The interfaces we given are not disposable but the underlying type can be.
        // This will ensure we dispose of any resources that need to be cleaned up.
        (readers.CoreReader as IDisposable)?.Dispose();
        (readers.ContentReader as IDisposable)?.Dispose();

        return (isDevDependency, tfms.ToImmutableArray());
    }

    internal static PackageReaders ReadPackage(string tempPackagePath)
    {
        var stream = new FileStream(
              tempPackagePath,
              FileMode.Open,
              FileAccess.Read,
              FileShare.Read,
              bufferSize: 4096);
        PackageArchiveReader archiveReader = new(stream);
        return (archiveReader, archiveReader);
    }

    internal static async Task<PackageReaders> DownloadPackageAsync(
        PackageIdentity package,
        NuGetContext context,
        CancellationToken cancellationToken)
    {
        var sourceMapping = PackageSourceMapping.GetPackageSourceMapping(context.Settings);
        var packageSources = sourceMapping.GetConfiguredPackageSources(package.Id).ToHashSet();
        var sources = packageSources.Count == 0
            ? context.PackageSources
            : context.PackageSources
                .Where(p => packageSources.Contains(p.Name))
                .ToImmutableArray();

        foreach (var source in sources)
        {
            var sourceRepository = Repository.Factory.GetCoreV3(source);
            var feed = await sourceRepository.GetResourceAsync<FindPackageByIdResource>();
            if (feed is null)
            {
                throw new NotSupportedException($"Failed to get FindPackageByIdResource for {source.SourceUri}");
            }

            try
            {
                // a non-compliant v2 API returning 404 can cause this to throw
                var exists = await feed.DoesPackageExistAsync(
                    package.Id,
                    package.Version,
                    context.SourceCacheContext,
                    NullLogger.Instance,
                    cancellationToken);
                if (!exists)
                {
                    continue;
                }
            }
            catch (FatalProtocolException)
            {
                // if anything goes wrong here, the package source obviously doesn't contain the requested package
                continue;
            }

            var downloader = await feed.GetPackageDownloaderAsync(
                package,
                context.SourceCacheContext,
                context.Logger,
                cancellationToken);

            var tempPackagePath = GetTempPackagePath(package, context);
            var isDownloaded = await downloader.CopyNupkgFileToAsync(tempPackagePath, cancellationToken);
            if (!isDownloaded)
            {
                throw new Exception($"Failed to download package [{package.Id}/{package.Version}] from [${source.SourceUri}]");
            }

            return (downloader.CoreReader, downloader.ContentReader);
        }

        throw new Exception($"Package [{package.Id}/{package.Version}] does not exist in any of the configured sources.");
    }

    internal static string GetTempPackagePath(PackageIdentity package, NuGetContext context)
        => Path.Combine(context.TempPackageDirectory, package.Id + "." + package.Version + ".nupkg");
}
