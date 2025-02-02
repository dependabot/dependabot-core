using NuGetUpdater.Core.FrameworkChecker;

using Xunit;

namespace NuGetUpdater.Core.Test.FrameworkChecker;

public class CompatibilityCheckerFacts
{
    [Theory]
    [InlineData("net8.0", "net8.0")]
    [InlineData("net8.0", "net7.0")]
    [InlineData("net7.0", "net7.0")]
    [InlineData("net7.0", "net6.0")]
    [InlineData("net7.0", "net5.0")]
    [InlineData("net7.0", "netcoreapp3.1")]
    [InlineData("net7.0", "netstandard2.1")]
    [InlineData("net7.0", "netstandard2.0")]
    [InlineData("net7.0", "netstandard1.3")]
    [InlineData("net4.8", "netstandard2.0")]
    [InlineData("net4.8", "netstandard1.3")]
    public void PackageContainsCompatibleFramework(string projectTfm, string packageTfm)
    {
        var result = CompatibilityChecker.IsCompatible([projectTfm], [packageTfm], new TestLogger());

        Assert.True(result);
    }

    [Theory]
    [InlineData("net48", "netcoreapp3.1")]
    [InlineData("net48", "netstandard2.1")]
    [InlineData("net7.0", "net8.0")]
    [InlineData("net6.0", "net7.0")]
    [InlineData("net5.0", "net6.0")]
    [InlineData("netcoreapp3.1", "net5.0")]
    [InlineData("netstandard2.0", "netstandard2.1")]
    [InlineData("netstandard1.3", "netstandard2.0")]
    [InlineData("net7.0", "net48")]
    public void PackageContainsIncompatibleFramework(string projectTfm, string packageTfm)
    {
        var result = CompatibilityChecker.IsCompatible([projectTfm], [packageTfm], new TestLogger());

        Assert.False(result);
    }

    [Theory]
    [InlineData(new[] { "net8.0", "net7.0", "net472" }, new[] { "netstandard2.0" })]
    [InlineData(new[] { "net8.0", "net7.0", "net472" }, new[] { "net5.0", "net461" })]
    [InlineData(new[] { "net6.0", "net6.0-windows10.0.19041" }, new[] { "net6.0", ".NETStandard2.0" })]
    public void PackageContainsCompatibleFrameworks(string[] projectTfms, string[] packageTfms)
    {
        var result = CompatibilityChecker.IsCompatible(projectTfms, packageTfms, new TestLogger());

        Assert.True(result);
    }

    [Theory]
    [InlineData(new[] { "net7.0", "net472" }, new[] { "net5.0" })]
    public void PackageContainsIncompatibleFrameworks(string[] projectTfms, string[] packageTfms)
    {
        var result = CompatibilityChecker.IsCompatible(projectTfms, packageTfms, new TestLogger());

        Assert.False(result);
    }
}
