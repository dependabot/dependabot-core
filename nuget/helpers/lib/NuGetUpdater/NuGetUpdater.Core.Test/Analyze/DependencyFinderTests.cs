using System.Collections.Immutable;

using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public class DependencyFinderTests : TestBase
{
    private static readonly string[] PackageNames = Enumerable.Range(0, 8).Select(i => $"Package.{i}").ToArray();

    [Fact]
    public async Task EnrichesDependenciesConcurrentlyInOrderAndReusesCachedResultsAcrossFrameworks()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        using var directory = await CreateProjectAsync();
        var responses = new GatedRequests<IPackageSearchMetadata>(PackageNames);
        using var context = CreateContext(directory.DirectoryPath, responses);
        var dependenciesTask = FindDependenciesAsync(directory.DirectoryPath, context, ["net8.0", "net9.0"], cancellationToken);
        try
        {
            for (var batch = 0; batch < 2; batch++)
            {
                var requests = await responses.ReadRequestsAsync(4, cancellationToken);
                Assert.Equal(4, responses.PeakConcurrency);
                foreach (var name in requests.Reverse())
                {
                    responses.Respond(name, CreateMetadata(name));
                }
            }

            var dependencies = await dependenciesTask.WaitAsync(cancellationToken);
            Assert.Equal(2, dependencies.Count);
            foreach (var framework in new[] { "net8.0", "net9.0" })
            {
                Assert.Equal(PackageNames, dependencies[framework].Select(d => d.Name));
                Assert.All(dependencies[framework], dependency =>
                {
                    Assert.Equal("1.0.0", dependency.Version);
                    Assert.True(dependency.IsTopLevel);
                    Assert.Equal([framework], dependency.TargetFrameworks);
                    Assert.Equal(CreateMetadata(dependency.Name).ProjectUrl?.ToString(), dependency.InfoUrl);
                });
            }

            Assert.Equal(8, responses.RequestCount);
            Assert.Equal(0, responses.ActiveRequests);
        }
        finally
        {
            responses.RespondAll(CreateMetadata);
            await dependenciesTask.WaitAsync(cancellationToken);
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task LookupFailureOrCancellationPropagatesAfterStartedRequestsSettle(bool cancel)
    {
        using var cancellationSource = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);
        using var directory = await CreateProjectAsync();
        var responses = new GatedRequests<IPackageSearchMetadata>(PackageNames);
        using var context = CreateContext(directory.DirectoryPath, responses);
        var dependenciesTask = FindDependenciesAsync(directory.DirectoryPath, context, ["net8.0"], cancellationSource.Token);
        try
        {
            var requests = await responses.ReadRequestsAsync(4, TestContext.Current.CancellationToken);
            if (cancel)
            {
                await cancellationSource.CancelAsync();
                await Assert.ThrowsAnyAsync<OperationCanceledException>(() => dependenciesTask);
            }
            else
            {
                responses.Fail(requests[0], new HttpRequestException("Package metadata is unavailable."));
                await Assert.ThrowsAsync<HttpRequestException>(() => dependenciesTask);
            }

            Assert.Equal(0, responses.ActiveRequests);
            Assert.Equal(4, responses.RequestCount);
        }
        finally
        {
            responses.RespondAll(CreateMetadata);
            if (!dependenciesTask.IsCompleted)
            {
                await dependenciesTask.WaitAsync(TestContext.Current.CancellationToken);
            }
        }
    }

    private static Task<ImmutableDictionary<string, ImmutableArray<Dependency>>> FindDependenciesAsync(
        string directory,
        NuGetContext context,
        string[] frameworks,
        CancellationToken cancellationToken) =>
        DependencyFinder.GetDependenciesAsync(
            directory,
            Path.Combine(directory, "project.csproj"),
            frameworks,
            PackageNames.ToImmutableHashSet(StringComparer.OrdinalIgnoreCase),
            NuGetVersion.Parse("1.0.0"),
            context,
            new TestLogger(),
            cancellationToken);

    private static async Task<TemporaryDirectory> CreateProjectAsync()
    {
        var directory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
            </Project>
            """));
        var packages = PackageNames.Select(name => MockNuGetPackage.CreateSimplePackage(name, "1.0.0", "net8.0")).ToArray();
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, directory.DirectoryPath);
        return directory;
    }

    private static NuGetContext CreateContext(string directory, GatedRequests<IPackageSearchMetadata> responses) =>
        new(directory, sourceRepositoryFactory: source => new SourceRepository(source,
        [
            new ResourceProvider<MetadataResource>(new ExistingMetadataResource()),
            new ResourceProvider<DownloadResource>(null),
            new ResourceProvider<PackageMetadataResource>(new GatedMetadataResource(responses)),
        ]));

    private static IPackageSearchMetadata CreateMetadata(string name) =>
        new PackageSearchMetadataBuilder.ClonedPackageSearchMetadata()
        {
            Identity = new PackageIdentity(name, NuGetVersion.Parse("1.0.0")),
            ProjectUrl = name == "Package.3" ? null : new Uri($"https://example.com/{name}"),
        };

    private sealed class ResourceProvider<T>(T? resource) : INuGetResourceProvider where T : class, INuGetResource
    {
        public Type ResourceType => typeof(T);
        public string Name => typeof(T).Name;
        public IEnumerable<string> Before => [];
        public IEnumerable<string> After => [];

        public Task<Tuple<bool, INuGetResource?>> TryCreate(SourceRepository source, CancellationToken token) =>
            Task.FromResult(Tuple.Create(true, (INuGetResource?)resource));
    }

    private sealed class ExistingMetadataResource : MetadataResource
    {
        public override Task<bool> Exists(PackageIdentity identity, bool includeUnlisted, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            Task.FromResult(true);

        public override Task<bool> Exists(string packageId, bool includePrerelease, bool includeUnlisted, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            Task.FromResult(true);

        public override Task<IEnumerable<NuGetVersion>> GetVersions(string packageId, bool includePrerelease, bool includeUnlisted, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            Task.FromResult<IEnumerable<NuGetVersion>>([]);

        public override Task<IEnumerable<KeyValuePair<string, NuGetVersion>>> GetLatestVersions(IEnumerable<string> packageIds, bool includePrerelease, bool includeUnlisted, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            Task.FromResult<IEnumerable<KeyValuePair<string, NuGetVersion>>>([]);
    }

    private sealed class GatedMetadataResource(GatedRequests<IPackageSearchMetadata> responses) : PackageMetadataResource
    {
        public override Task<IEnumerable<IPackageSearchMetadata>> GetMetadataAsync(string packageId, bool includePrerelease, bool includeUnlisted, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            Task.FromResult<IEnumerable<IPackageSearchMetadata>>([]);

        public override Task<IPackageSearchMetadata> GetMetadataAsync(PackageIdentity package, SourceCacheContext sourceCacheContext, NuGet.Common.ILogger log, CancellationToken token) =>
            responses.GetResponseAsync(package.Id, token);
    }
}
