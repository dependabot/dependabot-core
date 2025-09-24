using System.Collections.Immutable;
using System.Text;
using System.Text.Json;

using NuGet;
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
        var versionResult = await VersionFinder.GetVersionsByNameAsync(projectTfms, packageId, currentVersion, nugetContext, logger, CancellationToken.None);
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
            await VersionFinder.GetVersionsAsync([tfm], dependencyInfo, DateTimeOffset.UtcNow, nugetContext, logger, CancellationToken.None);
        });
        var error = JobErrorBase.ErrorFromException(exception, "TEST-JOB-ID", tempDir.DirectoryPath);

        // assert
        var expected = new PrivateSourceBadResponse([feedUrl]);
        var expectedJson = JsonSerializer.Serialize(expected, RunWorker.SerializerOptions);
        var actualJson = JsonSerializer.Serialize(error, RunWorker.SerializerOptions);
        Assert.Equal(expectedJson, actualJson);
    }

    [Theory]
    [InlineData(null, "1.0.1", "1.1.0", "2.0.0")]
    [InlineData(ConditionUpdateType.SemVerMajor, "1.0.1", "1.1.0")]
    [InlineData(ConditionUpdateType.SemVerMinor, "1.0.1")]
    [InlineData(ConditionUpdateType.SemVerPatch)]
    public async Task VersionFinder_IgnoredUpdateTypesIsHonored(ConditionUpdateType? ignoredUpdateType, params string[] expectedVersions)
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([
            MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.1", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.1.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
        ], tempDir.DirectoryPath);
        var tfm = NuGetFramework.Parse("net9.0");
        var ignoredUpdateTypes = ignoredUpdateType is not null
            ? new ConditionUpdateType[] { ignoredUpdateType.Value }
            : [];
        var dependencyInfo = new DependencyInfo()
        {
            Name = "Some.Dependency",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
            IgnoredUpdateTypes = [.. ignoredUpdateTypes],
        };
        var logger = new TestLogger();
        var nugetContext = new NuGetContext(tempDir.DirectoryPath);

        // act
        var versionResult = await VersionFinder.GetVersionsAsync([tfm], dependencyInfo, DateTimeOffset.UtcNow, nugetContext, logger, CancellationToken.None);
        var versions = versionResult.GetVersions();

        // assert
        var actualVersions = versions.Select(v => v.ToString()).OrderBy(v => v).ToArray();
        AssertEx.Equal(expectedVersions, actualVersions);
    }

    [Fact]
    public async Task CooldownValuesAreHonored()
    {
        // updating from version 1.0.0 only to 1.2.0 because the cooldown settings prohibit major updates

        // arrange
        var tfm = "net8.0";
        var packageVersionsAndDates = new[]
        {
            // major = month, minor = day, patch = hour
            ("1.1.0", "\"2025-01-01T00:00:00.00+00:00\""),
            ("1.1.1", "\"2025-01-01T01:00:00.00+00:00\""),
            ("1.2.0", "\"2025-01-02T00:00:00.00+00:00\""),
            ("1.3.0", "null"),
            ("2.1.0", "\"2025-02-01T00:00:00.00+00:00\""),
        };
        var cooldown = new Cooldown()
        {
            DefaultDays = 1,
            SemVerMajorDays = 10,
            SemVerMinorDays = 1,
            SemVerPatchDays = 1,
            Include = ["Some.Package"],
        };
        // can only update a major version if 10 days have passed since the publish date, but it's currently only 7 days after the publish date
        var currentTime = DateTimeOffset.Parse(packageVersionsAndDates.Last().Item2.Trim('"')).AddDays(7);
        using var http = TestHttpServer.CreateTestServer(url =>
        {
            var uri = new Uri(url, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                "/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/base",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl/3.6.0"
                            }
                        ]
                    }
                    """)),
                "/base/some.package/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                      "versions": [{{string.Join(", ", packageVersionsAndDates.Select(d => $"\"{d.Item1}\""))}}]
                    }
                    """)),
                "/base/some.package/1.1.0/some.package.1.1.0.nupkg" => (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", tfm).GetZipStream().ReadAllBytes()),
                "/base/some.package/1.1.1/some.package.1.1.1.nupkg" => (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.1", tfm).GetZipStream().ReadAllBytes()),
                "/base/some.package/1.2.0/some.package.1.2.0.nupkg" => (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.0", tfm).GetZipStream().ReadAllBytes()),
                "/base/some.package/1.3.0/some.package.1.3.0.nupkg" => (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.3.0", tfm).GetZipStream().ReadAllBytes()),
                "/base/some.package/2.1.0/some.package.2.1.0.nupkg" => (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "2.1.0", tfm).GetZipStream().ReadAllBytes()),
                "/registrations/some.package/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                      "count": 1,
                      "items": [
                        {
                          "count": {{packageVersionsAndDates.Length}},
                          "lower": "{{packageVersionsAndDates.First().Item1}}",
                          "upper": "{{packageVersionsAndDates.Last().Item1}}",
                          "items": [
                            {{string.Join(", ", packageVersionsAndDates.Select(d => $$"""
                                {
                                  "catalogEntry": {
                                    "id": "Some.Package",
                                    "version": "{{d.Item1}}",
                                    "published": {{d.Item2}}
                                  }
                                }
                                """))}}
                          ]
                        }
                      ]
                    }
                    """)),
                _ => (404, Encoding.UTF8.GetBytes("{}"))
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
        var currentVersion = NuGetVersion.Parse("1.0.0");
        var dependencyInfo = new DependencyInfo()
        {
            Name = "Some.Package",
            Version = currentVersion.ToString(),
            IsVulnerable = false,
            Cooldown = cooldown,
        };
        var logger = new TestLogger();
        var nugetContext = new NuGetContext(tempDir.DirectoryPath);
        var versionResult = await VersionFinder.GetVersionsAsync([NuGetFramework.Parse(tfm)], dependencyInfo, currentVersion, currentTime, nugetContext, logger, CancellationToken.None);
        var versions = versionResult.GetVersions();

        // assert
        // including 1.3.0 because the publish date was null
        // not including 2.1.0 because the major update isn't allowed yet
        var expected = new[] { "1.1.0", "1.1.1", "1.2.0", "1.3.0" };
        var actual = versions.Select(v => v.ToString()).ToArray();
        AssertEx.Equal(expected, actual);
    }
}
