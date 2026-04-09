using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public class CompatibilityCheckerTests
{
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
}
