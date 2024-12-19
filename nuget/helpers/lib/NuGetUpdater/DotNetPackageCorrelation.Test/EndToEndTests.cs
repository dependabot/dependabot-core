using System.Runtime.CompilerServices;

using Semver;

using Xunit;

namespace DotNetPackageCorrelation.Tests;

public class EndToEndTests
{
    [Fact]
    public async Task IntegrationTest()
    {
        // arrange
        var thisFileDirectory = Path.GetDirectoryName(GetThisFilePath())!;
        var dotnetCoreDirectory = Path.Combine(thisFileDirectory, "..", "..", "dotnet-core");
        var correlator = new Correlator(new DirectoryInfo(Path.Combine(dotnetCoreDirectory, "release-notes")));

        // act
        var (runtimePackages, _warnings) = await correlator.RunAsync();
        var packageMapper = PackageMapper.Load(runtimePackages);

        // assert
        // Microsoft.NETCore.App.Ref/8.0.8 didn't ship with System.Text.Json, but the previous version 8.0.7 shipped at the same time as System.Text.Json/8.0.4
        var systemTextJsonVersion = packageMapper.GetPackageVersionThatShippedWithOtherPackage("Microsoft.NETCore.App.Ref", SemVersion.Parse("8.0.8"), "System.Text.Json");
        Assert.Equal("8.0.4", systemTextJsonVersion?.ToString());
    }

    private static string GetThisFilePath([CallerFilePath] string? path = null) => path ?? throw new ArgumentNullException(nameof(path));
}
