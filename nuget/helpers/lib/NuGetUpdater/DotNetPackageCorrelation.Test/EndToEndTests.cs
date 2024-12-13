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
        var (packages, _warnings) = await correlator.RunAsync();
        var sdkVersion = SemVersion.Parse("8.0.307");

        // SDK 8.0.307 has no System.Text.Json, but 8.0.306 provides System.Text.Json 8.0.5
        var systemTextJsonPackageVersion = packages.GetReplacementPackageVersion(sdkVersion, "system.TEXT.json");

        // assert
        Assert.Equal("8.0.5", systemTextJsonPackageVersion?.ToString());
    }

    private static string GetThisFilePath([CallerFilePath] string? path = null) => path ?? throw new ArgumentNullException(nameof(path));
}
