using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public class CompatibilityCheckerTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ExistsAsync_ResourceLookupReceivesCancellationToken(bool packageIsCached)
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="test" value="https://example.com/v3/index.json" />
                  </packageSources>
                </configuration>
                """)
        );
        var resourceProvider = new CapturingResourceProvider<FindPackageByIdResource>(
            new MissingFindPackageByIdResource());
        using var context = new NuGetContext(
            tempDir.DirectoryPath,
            sourceRepositoryFactory: source => new SourceRepository(source, [resourceProvider]));
        var package = MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net9.0");
        var packageIdentity = new PackageIdentity(package.Id, NuGetVersion.Parse(package.Version));
        if (packageIsCached)
        {
            var packagePath = CompatibilityChecker.GetPackagePath(packageIdentity, context);
            using var packageStream = package.GetZipStream();
            using var cacheStream = File.Create(packagePath);
            await packageStream.CopyToAsync(cacheStream, TestContext.Current.CancellationToken);
        }

        using var cancellationSource = CancellationTokenSource.CreateLinkedTokenSource(
            TestContext.Current.CancellationToken);
        var exists = await CompatibilityChecker.ExistsAsync(
            packageIdentity,
            context,
            cancellationSource.Token);

        Assert.False(exists);
        Assert.Equal(cancellationSource.Token, resourceProvider.ReceivedToken);
    }

    [Fact]
    public void PerformCheck_CompatiblePackage_IsCompatible()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [
            NuGetFramework.Parse("net6.0"),
            NuGetFramework.Parse("netstandard2.0"),
        ];
        var isDevDependency = false;
        ImmutableArray<NuGetFramework> packageFrameworks = [
            NuGetFramework.Parse("netstandard1.3"),
        ];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.True(result);
    }

    [Fact]
    public void PerformCheck_IncompatiblePackage_IsIncompatible()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [
            NuGetFramework.Parse("net6.0"),
            NuGetFramework.Parse("netstandard2.0"),
        ];
        var isDevDependency = false;
        ImmutableArray<NuGetFramework> packageFrameworks = [
            NuGetFramework.Parse("net462"),
        ];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.False(result);
    }

    [Fact]
    public void PerformCheck_DevDependencyWithPackageFrameworks_IsChecked()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [
            NuGetFramework.Parse("net6.0"),
            NuGetFramework.Parse("netstandard2.0"),
        ];
        var isDevDependency = true;
        ImmutableArray<NuGetFramework> packageFrameworks = [
            NuGetFramework.Parse("net462"),
        ];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.False(result);
    }

    [Fact]
    public void PerformCheck_DevDependencyWithoutPackageFrameworks_IsCompatibile()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [
            NuGetFramework.Parse("net6.0"),
            NuGetFramework.Parse("netstandard2.0"),
        ];
        var isDevDependency = true;
        ImmutableArray<NuGetFramework> packageFrameworks = [];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.True(result);
    }

    [Fact]
    public void PerformCheck_WithoutPackageFrameworks_IsIncompatibile()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [
            NuGetFramework.Parse("net6.0"),
            NuGetFramework.Parse("netstandard2.0"),
        ];
        var isDevDependency = false;
        ImmutableArray<NuGetFramework> packageFrameworks = [];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.False(result);
    }

    [Fact]
    public void PerformCheck_WithoutProjectFrameworks_IsIncompatible()
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [];
        var isDevDependency = true;
        ImmutableArray<NuGetFramework> packageFrameworks = [
            NuGetFramework.Parse("netstandard1.3"),
        ];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.False(result);
    }

    [Fact]
    public async Task CheckAsync_PackageWithFrameworkDependencyGroupButNoAssemblies_ReportsAsCompatible()
    {
        // package has an explicit dependency group that is incompatible with the project framework, but lib and ref directories are empty
        // a real-world example is a project targeting `net9.0` and referencing `Microsoft.VisualStudio.Azure.Containers.Tools.Targets/1.22.1`
        // depending on the project's properties, it's entirely possible for this to be a supported scenario

        // arrange
        using var tempDir = new TemporaryDirectory();
        var package = new MockNuGetPackage("Some.Package", "1.0.0", DependencyGroups: [(".NETFramework4.7.2", [])]);
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([package], tempDir.DirectoryPath, includeCommonPackages: false);

        var packageId = new PackageIdentity(package.Id, NuGetVersion.Parse(package.Version));
        var projectFramework = NuGetFramework.Parse("net9.0");
        var context = new NuGetContext(tempDir.DirectoryPath, NuGet.Common.NullLogger.Instance);
        var logger = new TestLogger();

        // act
        var isCompatible = await CompatibilityChecker.CheckAsync(packageId, [projectFramework], context, logger, CancellationToken.None);

        //assert
        Assert.True(isCompatible);
    }

    [Fact]
    public async Task ExistsAndIsCompatibleAsync_ExistingPackageWithoutProjectFrameworks_ReportsAsCompatible()
    {
        using var tempDir = new TemporaryDirectory();
        var package = MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net9.0");
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([package], tempDir.DirectoryPath, includeCommonPackages: false);
        var packageId = new PackageIdentity(package.Id, NuGetVersion.Parse(package.Version));
        var context = new NuGetContext(tempDir.DirectoryPath, NuGet.Common.NullLogger.Instance);

        var isCompatible = await CompatibilityChecker.ExistsAndIsCompatibleAsync(
            packageId,
            projectFrameworks: [],
            context,
            new TestLogger(),
            CancellationToken.None);

        Assert.True(isCompatible);
    }

    [Theory]
    [InlineData("netstandard2.0")]
    [InlineData("net472")]
    [InlineData("net6.0")]
    [InlineData("net7.0")]
    [InlineData("net8.0")]
    public void EverythingIsCompatibleWithAnyVersion0Framework(string projectFramework)
    {
        var package = new PackageIdentity("Dependency", NuGetVersion.Parse("1.0.0"));
        ImmutableArray<NuGetFramework> projectFrameworks = [NuGetFramework.Parse(projectFramework)];
        var isDevDependency = false;
        ImmutableArray<NuGetFramework> packageFrameworks = [NuGetFramework.Parse("Any,Version=v0.0")];

        var result = CompatibilityChecker.PerformCheck(
            package,
            projectFrameworks,
            isDevDependency,
            packageFrameworks,
            new TestLogger());

        Assert.True(result);
    }

    private sealed class CapturingResourceProvider<TResource>(TResource resource) : INuGetResourceProvider
        where TResource : class, INuGetResource
    {
        public Type ResourceType => typeof(TResource);
        public string Name => typeof(TResource).Name;
        public IEnumerable<string> Before => [];
        public IEnumerable<string> After => [];
        public CancellationToken ReceivedToken { get; private set; }

        public Task<Tuple<bool, INuGetResource?>> TryCreate(
            SourceRepository source,
            CancellationToken token)
        {
            ReceivedToken = token;
            return Task.FromResult(Tuple.Create(true, (INuGetResource?)resource));
        }
    }

    private sealed class MissingFindPackageByIdResource : FindPackageByIdResource
    {
        public override Task<IEnumerable<NuGetVersion>> GetAllVersionsAsync(
            string id,
            SourceCacheContext cacheContext,
            NuGet.Common.ILogger logger,
            CancellationToken cancellationToken) => throw new NotImplementedException();

        public override Task<FindPackageByIdDependencyInfo> GetDependencyInfoAsync(
            string id,
            NuGetVersion version,
            SourceCacheContext cacheContext,
            NuGet.Common.ILogger logger,
            CancellationToken cancellationToken) => throw new NotImplementedException();

        public override Task<bool> CopyNupkgToStreamAsync(
            string id,
            NuGetVersion version,
            Stream destination,
            SourceCacheContext cacheContext,
            NuGet.Common.ILogger logger,
            CancellationToken cancellationToken) => throw new NotImplementedException();

        public override Task<IPackageDownloader> GetPackageDownloaderAsync(
            PackageIdentity packageIdentity,
            SourceCacheContext cacheContext,
            NuGet.Common.ILogger logger,
            CancellationToken cancellationToken) => throw new NotImplementedException();

        public override Task<bool> DoesPackageExistAsync(
            string id,
            NuGetVersion version,
            SourceCacheContext cacheContext,
            NuGet.Common.ILogger logger,
            CancellationToken cancellationToken) => Task.FromResult(false);
    }
}
