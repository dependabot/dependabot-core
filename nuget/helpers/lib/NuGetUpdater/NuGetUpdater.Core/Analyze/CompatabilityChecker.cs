using System.Collections.Immutable;

using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;

using NuGetUpdater.Core;
using NuGetUpdater.Core.FrameworkChecker;

namespace NuGetUpdater.Analyzer;

using PackageInfo = (bool IsDevDependency, ImmutableArray<NuGetFramework> Frameworks);
using PackageReaders = (IAsyncPackageCoreReader CoreReader, IAsyncPackageContentReader ContentReader);

internal static class CompatibilityChecker
{
    public static async Task<bool> CheckAsync(
        PackageSource source,
        PackageIdentity package,
        ImmutableArray<NuGetFramework> projectFrameworks,
        NuGetContext context,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var (isDevDependency, packageFrameworks) = await GetPackageInfoAsync(
            source,
            package,
            context,
            cancellationToken);

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

        var incompatibleFrameworks = projectFrameworks.Where(f => !compatibleFrameworks.Contains(f)).ToArray();
        if (incompatibleFrameworks.Length > 0)
        {
            logger.Log($"The package {package} is not compatible. Incompatible project frameworks: {string.Join(", ", incompatibleFrameworks.Select(f => f.GetShortFolderName()))}");
            return false;
        }

        return true;
    }

    internal static async Task<PackageInfo> GetPackageInfoAsync(
        PackageSource source,
        PackageIdentity package,
        NuGetContext context,
        CancellationToken cancellationToken)
    {
        var tempPackagePath = GetTempPackagePath(package, context);
        var readers = File.Exists(tempPackagePath)
            ? ReadPackage(tempPackagePath)
            : await DownloadPackageAsync(source, package, context, cancellationToken);

        var nuspecStream = await readers.CoreReader.GetNuspecAsync(cancellationToken);
        var reader = new NuspecReader(nuspecStream);

        var isDevDependency = reader.GetDevelopmentDependency();

        var tfms = reader.GetDependencyGroups()
            .Select(d => d.TargetFramework)
            .ToImmutableArray();
        if (tfms.Length == 0)
        {
            // If the nuspec doesn't have any dependency groups,
            // try to get the TargetFramework from files in the lib folder.
            var libItems = (await readers.ContentReader.GetLibItemsAsync(cancellationToken)).ToList();
            if (libItems.Count == 0)
            {
                // If there is no lib folder in this package, then assume it is a dev dependency.
                isDevDependency = true;
            }

            tfms = libItems.Select(item => item.TargetFramework)
                .Distinct()
                .ToImmutableArray();
        }

        // The interfaces we given are not disposable but the underlying type can be.
        // This will ensure we dispose of any resources that need to be cleaned up.
        (readers.CoreReader as IDisposable)?.Dispose();
        (readers.ContentReader as IDisposable)?.Dispose();

        return (isDevDependency, tfms);
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
        PackageSource source,
        PackageIdentity package,
        NuGetContext context,
        CancellationToken cancellationToken)
    {
        var sourceRepository = Repository.Factory.GetCoreV3(source);
        var feed = await sourceRepository.GetResourceAsync<FindPackageByIdResource>();
        if (feed is null)
        {
            throw new NotSupportedException($"Failed to get FindPackageByIdResource for {source.SourceUri}");
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
            throw new Exception("Failed to download package");
        }

        return (downloader.CoreReader, downloader.ContentReader);
    }

    internal static string GetTempPackagePath(PackageIdentity package, NuGetContext context)
        => Path.Combine(context.TempPackageDirectory, package.Id + "." + package.Version + ".nupkg");
}
