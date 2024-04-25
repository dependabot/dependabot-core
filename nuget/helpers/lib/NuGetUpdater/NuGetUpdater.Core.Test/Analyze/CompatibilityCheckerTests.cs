using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

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
            new Logger(verbose: false));

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
            new Logger(verbose: false));

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
            new Logger(verbose: false));

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
            new Logger(verbose: false));

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
            new Logger(verbose: false));

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
            new Logger(verbose: false));

        Assert.False(result);
    }
}
