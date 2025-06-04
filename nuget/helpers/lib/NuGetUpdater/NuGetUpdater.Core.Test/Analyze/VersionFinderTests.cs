using System.Collections.Immutable;
using System.Text.Json;

using NuGet.Frameworks;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public class VersionFinderTests : TestBase
{
    [Fact]
    public void VersionFilter_VersionInIgnoredVersions_ReturnsFalse()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "0.8.0",
            IsVulnerable = false,
            IgnoredVersions = [Requirement.Parse("< 1.0.0")],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("0.9.0");

        var result = filter(version);

        Assert.False(result);
    }

    [Fact]
    public void VersionFilter_VersionNotInIgnoredVersions_ReturnsTrue()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "0.8.0",
            IsVulnerable = false,
            IgnoredVersions = [Requirement.Parse("< 1.0.0")],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.1");

        var result = filter(version);

        Assert.True(result);
    }

    [Fact]
    public void VersionFilter_VersionInVulnerabilities_ReturnsFalse()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "0.8.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [new()
            {
                DependencyName = "Dependency",
                PackageManager = "PackageManager",
                SafeVersions = [],
                VulnerableVersions = [Requirement.Parse("< 1.0.0")],
            }],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("0.9.0");

        var result = filter(version);

        Assert.False(result);
    }

    [Fact]
    public void VersionFilter_VersionNotInVulnerabilities_ReturnsTrue()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "0.8.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [new()
            {
                DependencyName = "Dependency",
                PackageManager = "PackageManager",
                SafeVersions = [],
                VulnerableVersions = [Requirement.Parse("< 1.0.0")],
            }],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.1");

        var result = filter(version);

        Assert.True(result);
    }

    [Fact]
    public void VersionFilter_VersionLessThanCurrentVersion_ReturnsFalse()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("0.9.0");

        var result = filter(version);

        Assert.False(result);
    }

    [Fact]
    public void VersionFilter_VersionHigherThanCurrentVersion_ReturnsTrue()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.1");

        var result = filter(version);

        Assert.True(result);
    }

    [Fact]
    public void VersionFilter_PreviewVersionDifferentThanCurrentVersion_ReturnsFalse()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "1.0.0-alpha",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.1-beta");

        var result = filter(version);

        Assert.False(result);
    }

    [Fact]
    public void VersionFilter_PreviewVersionSameAsCurrentVersion_ReturnsTrue()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "1.0.0-alpha",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.0-beta");

        var result = filter(version);

        Assert.True(result);
    }

    [Fact]
    public void VersionFilter_WildcardPreviewVersion_ReturnsTrue()
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = "Dependency",
            Version = "*-*",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var filter = VersionFinder.CreateVersionFilter(dependencyInfo, VersionRange.Parse(dependencyInfo.Version));
        var version = NuGetVersion.Parse("1.0.0-beta");

        var result = filter(version);

        Assert.True(result);
    }

    [Fact]
    public async Task TargetFrameworkIsConsideredForUpdatedVersions()
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"), // can only update to this version because of the tfm
                MockNuGetPackage.CreateSimplePackage("Some.Package", "3.0.0", "net9.0"),
            ],
            tempDir.DirectoryPath);

        // act
        var projectTfms = new[] { "net8.0" }.Select(NuGetFramework.Parse).ToImmutableArray();
        var packageId = "Some.Package";
        var currentVersion = NuGetVersion.Parse("1.0.0");
        var logger = new TestLogger();
        var nugetContext = new NuGetContext(tempDir.DirectoryPath);
        var versionResult = await VersionFinder.GetVersionsAsync(projectTfms, packageId, currentVersion, nugetContext, logger, CancellationToken.None);
        var versions = versionResult.GetVersions();

        // assert
        var actual = versions.Select(v => v.ToString()).ToArray();
        var expected = new[] { "2.0.0" };
        AssertEx.Equal(expected, actual);
    }

    [Fact]
    public async Task FeedReturnsBadJson()
    {
        // arrange
        using var http = TestHttpServer.CreateTestStringServer(url =>
        {
            var uri = new Uri(url, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                // initial and search query are good, update should be possible...
                "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                _ => (200, "") // empty string instead of expected JSON object
            };
        });
        var feedUrl = $"{http.BaseUrl.TrimEnd('/')}/index.json";
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", $"""
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="private_feed" value="{feedUrl}" allowInsecureConnections="true" />
                  </packageSources>
                </configuration>
                """)
        );

        // act
        var tfm = NuGetFramework.Parse("net9.0");
        var dependencyInfo = new DependencyInfo
        {
            Name = "Some.Dependency",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var logger = new TestLogger();
        var nugetContext = new NuGetContext(tempDir.DirectoryPath);
        var exception = await Assert.ThrowsAsync<BadResponseException>(async () =>
        {
            await VersionFinder.GetVersionsAsync([tfm], dependencyInfo, nugetContext, logger, CancellationToken.None);
        });
        var error = JobErrorBase.ErrorFromException(exception, "TEST-JOB-ID", tempDir.DirectoryPath);

        // assert
        var expected = new PrivateSourceBadResponse([feedUrl]);
        var expectedJson = JsonSerializer.Serialize(expected, RunWorker.SerializerOptions);
        var actualJson = JsonSerializer.Serialize(error, RunWorker.SerializerOptions);
        Assert.Equal(expectedJson, actualJson);
    }
}
