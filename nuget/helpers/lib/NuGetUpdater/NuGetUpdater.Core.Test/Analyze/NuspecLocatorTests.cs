using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

using TestFile = (string Path, string Content);

public class NuspecLocatorTests
{
    internal const string NuGetOrgFeedUrl = "https://api.nuget.org/v3/index.json";
    internal const string DotNetToolsFeedUrl = "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json";

    [Fact]
    public async Task LocateNuspec_ReturnsUrl_ForNuGetOrgFeed()
    {
        await TestLocateAsync(
            [NuGetOrgFeedUrl],
            "Microsoft.CodeAnalysis.Common",
            NuGetVersion.Parse("4.9.2"),
            "https://api.nuget.org/v3-flatcontainer/microsoft.codeanalysis.common/4.9.2/microsoft.codeanalysis.common.nuspec");
    }

    [Fact]
    public async Task LocateNuspec_ReturnsUrl_ForAzureArtifactsFeed()
    {
        await TestLocateAsync(
            [NuGetOrgFeedUrl, DotNetToolsFeedUrl],
            "Microsoft.CodeAnalysis.Common",
            NuGetVersion.Parse("4.11.0-1.24219.1"),
            "https://pkgs.dev.azure.com/dnceng/9ee6d478-d288-47f7-aacc-f6e6d082ae6d/_packaging/d1622942-d16f-48e5-bc83-96f4539e7601/nuget/v3/flat2/microsoft.codeanalysis.common/4.11.0-1.24219.1/microsoft.codeanalysis.common.nuspec");
    }

    [Fact]
    public async Task LocateNuspec_ReturnsNull_ForInvalidFeed()
    {
        await TestLocateAsync(
            ["https:://invalid-feed-url"],
            "Microsoft.CodeAnalysis.Common",
            NuGetVersion.Parse("4.9.2"),
            null);
    }

    [Fact]
    public async Task LocateNuspec_ReturnsNull_ForInvalidPackage()
    {
        await TestLocateAsync(
            [NuGetOrgFeedUrl],
            "Microsoft.CodeAnalysis.Invalid",
            NuGetVersion.Parse("4.9.2"),
            null);
    }

    protected static async Task TestLocateAsync(
        string[] feedUrls,
        string packageId,
        NuGetVersion version,
        string? expectedResult)
    {
        var currentDirectory = Environment.CurrentDirectory;

        TestFile[] files = [
            ("./nuget.config", $"""
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                    <packageSources>
                        <clear />
                        {string.Join(Environment.NewLine, feedUrls.Select((url, index) => $"<add key=\"feed{index}\" value=\"{url}\" />"))}
                    </packageSources>
                </configuration>
                """),
        ];

        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        try
        {
            Environment.CurrentDirectory = temporaryDirectory.DirectoryPath;
            var nugetContext = new NuGetContext();
            var logger = new Logger(verbose: true);

            var actual = await NuspecLocator.LocateNuspecAsync(
                packageId,
                version,
                nugetContext,
                logger,
                CancellationToken.None);

            Assert.Equal(expectedResult, actual);
        }
        finally
        {
            Environment.CurrentDirectory = currentDirectory;
        }
    }
}
