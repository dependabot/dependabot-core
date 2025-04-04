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
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var packageInfo = await GetPackageInfoAsync(
            package,
            nugetContext,
            cancellationToken);
        if (packageInfo is null)
        {
            return false;
        }

        var (isDevDependency, packageFrameworks) = packageInfo.GetValueOrDefault();
        return PerformCheck(package, projectFrameworks, isDevDependency, packageFrameworks, logger);
    }

    internal static bool PerformCheck(
        PackageIdentity package,
        ImmutableArray<NuGetFramework> projectFrameworks,
        bool isDevDependency,
        ImmutableArray<NuGetFramework> packageFrameworks,
        ILogger logger)
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
            logger.Info($"The package {package} is not compatible. Incompatible project frameworks: {string.Join(", ", incompatibleFrameworks.Select(f => f.GetShortFolderName()))}");
            return false;
        }

        return true;
    }

    internal static async Task<PackageReaders?> GetPackageReadersAsync(
        PackageIdentity package,
        NuGetContext nugetContext,
        CancellationToken cancellationToken)
    {
        var packagePath = GetPackagePath(package, nugetContext);
        var readers = File.Exists(packagePath)
            ? ReadPackage(packagePath)
            : await DownloadPackageAsync(package, nugetContext, cancellationToken);
        return readers;
    }

    internal static async Task<PackageInfo?> GetPackageInfoAsync(
        PackageIdentity package,
        NuGetContext nugetContext,
        CancellationToken cancellationToken)
    {
        var readersOption = await GetPackageReadersAsync(package, nugetContext, cancellationToken);
        if (readersOption is null)
        {
            return null;
        }

        var readers = readersOption.GetValueOrDefault();
        var nuspecStream = await readers.CoreReader.GetNuspecAsync(cancellationToken);
        var reader = new NuspecReader(nuspecStream);

        var isDevDependency = reader.GetDevelopmentDependency();
        var tfms = new HashSet<NuGetFramework>();
        var dependencyGroups = reader.GetDependencyGroups().ToArray();

        foreach (var d in dependencyGroups)
        {
            if (!d.TargetFramework.IsAny)
            {
                tfms.Add(d.TargetFramework);
            }
        }

        var refItems = await readers.ContentReader.GetReferenceItemsAsync(cancellationToken);
        foreach (var refItem in refItems)
        {
            tfms.Add(refItem.TargetFramework);
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

    internal static PackageReaders ReadPackage(string packagePath)
    {
        var stream = new FileStream(
              packagePath,
              FileMode.Open,
              FileAccess.Read,
              FileShare.Read,
              bufferSize: 4096);
        PackageArchiveReader archiveReader = new(stream);
        return (archiveReader, archiveReader);
    }

    internal static async Task<PackageReaders?> DownloadPackageAsync(
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

            var packagePath = GetPackagePath(package, context);
            var isDownloaded = await downloader.CopyNupkgFileToAsync(packagePath, cancellationToken);
            if (!isDownloaded)
            {
                continue;
            }

            return (downloader.CoreReader, downloader.ContentReader);
        }

        return null;
    }

    internal static string GetPackagePath(PackageIdentity package, NuGetContext context)
    {
        // https://learn.microsoft.com/en-us/nuget/consume-packages/managing-the-global-packages-and-cache-folders
        var nugetPackagesPath = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (nugetPackagesPath is null)
        {
            // n.b., this path should never be hit during a unit test
            nugetPackagesPath = Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
        }

        var normalizedName = package.Id.ToLowerInvariant();
        var normalizedVersion = package.Version.ToNormalizedString().ToLowerInvariant();
        var packageDirectory = Path.Join(nugetPackagesPath, normalizedName, normalizedVersion);
        Directory.CreateDirectory(packageDirectory);
        var packagePath = Path.Join(packageDirectory, $"{normalizedName}.{normalizedVersion}.nupkg");
        return packagePath;
    }
}
