using System.Collections.Immutable;

using NuGet.Common;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;

using NuGetUpdater.Core;

namespace NuGetUpdater.Analyzer;

internal static class DependencyFinder
{
    public static async Task<ImmutableArray<PackageDependency>> GetDependenciesAsync(
        PackageSource source,
        PackageIdentity package,
        NuGetFramework framework,
        NuGetContext context,
        Logger logger,
        CancellationToken cancellationToken)
    {
        var sourceRepository = Repository.Factory.GetCoreV3(source);
        var feed = await sourceRepository.GetResourceAsync<DependencyInfoResource>();
        if (feed is null)
        {
            throw new NotSupportedException($"Failed to get DependencyInfoResource for {source.SourceUri}");
        }

        var dependencyInfo = await feed.ResolvePackage(
            package,
            framework,
            context.SourceCacheContext,
            NullLogger.Instance,
            cancellationToken);
        if (dependencyInfo is null)
        {
            throw new Exception($"Failed to resolve package {package} from {source.SourceUri}");
        }

        return dependencyInfo.Dependencies
            .ToImmutableArray();
    }
}
