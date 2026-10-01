using System.Collections.Immutable;
using System.Text;
using System.Text.Json;

using NuGet;
using NuGet.Configuration;
using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
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
    public async Task CandidateVersionsAreNotFilteredByTargetFramework()
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "3.0.0", "net9.0"),
            ],
            tempDir.DirectoryPath);
        var dependencyInfo = new DependencyInfo()
        {
            Name = "Some.Package",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
        };
        var logger = new TestLogger();
        var nugetContext = new NuGetContext(tempDir.DirectoryPath);

        // act
        var versionResult = await VersionFinder.GetCandidateVersionsAsync(
            dependencyInfo,
            DateTimeOffset.UtcNow,
            nugetContext,
            logger,
            CancellationToken.None);

        // assert
        var actual = versionResult.GetVersions().Select(v => v.ToString()).ToArray();
        var expected = new[] { "2.0.0", "3.0.0" };
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
        var expected = new PrivateSourceBadResponse([feedUrl], "unused");
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

    [Fact]
    public async Task MisbehavingNuGetFeedDoesNotPreventFindingVersions()
    {
        using var http = TestHttpServer.CreateTestStringServer(url =>
        {
            var uri = new Uri(url, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                // registration index returns a range with @id but no inlined items;
                // this causes the URL specified in @id to be queried but if that isn't present, the NuGet libraries will eventually throw
                "/registrations/some.package/index.json" => (200, $$"""
                    {
                        "count": 1,
                        "items": [
                            {
                                "@id": "{{baseUrl}}/registrations/some.package/page1.json",
                                "lower": "1.0.0",
                                "upper": "2.0.0"
                            }
                        ]
                    }
                    """),
                _ => (404, "")
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

        var context = new NuGetContext(tempDir.DirectoryPath);

        var projectTfm = NuGetFramework.Parse("net9.0");
        var dependencyInfo = new DependencyInfo()
        {
            Name = "Some.Package",
            Version = "1.0.0",
            IsVulnerable = false,
        };
        var currentVersion = NuGetVersion.Parse(dependencyInfo.Version);
        var versionsResult = await VersionFinder.GetVersionsAsync([projectTfm], dependencyInfo, currentVersion, DateTime.Now, context, new TestLogger(), CancellationToken.None);
        Assert.NotNull(versionsResult);
        var versions = versionsResult.GetVersions();
        Assert.Empty(versions);
    }

    [Fact]
    public async Task CooldownMetadataLookupReceivesCancellationToken()
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
        var metadataResource = new CountingMetadataResource([NuGetVersion.Parse("1.1.0")]);
        var packageMetadataResource = new CapturingPackageMetadataResource();
        using var context = new NuGetContext(
            tempDir.DirectoryPath,
            sourceRepositoryFactory: source => new SourceRepository(
                source,
                [
                    new TestResourceProvider<MetadataResource>(metadataResource),
                    new TestResourceProvider<PackageMetadataResource>(packageMetadataResource),
                ]));
        var dependencyInfo = new DependencyInfo
        {
            Name = "Some.Package",
            Version = "1.0.0",
            IsVulnerable = false,
            IgnoredVersions = [],
            Vulnerabilities = [],
            Cooldown = new Cooldown
            {
                DefaultDays = 0,
                Include = ["Some.Package"],
                Exclude = [],
            },
        };
        using var cancellationSource = CancellationTokenSource.CreateLinkedTokenSource(
            TestContext.Current.CancellationToken);

        var result = await VersionFinder.GetCandidateVersionsAsync(
            dependencyInfo,
            DateTimeOffset.UtcNow,
            context,
            new TestLogger(),
            cancellationSource.Token);

        Assert.Contains(NuGetVersion.Parse("1.1.0"), result.GetVersions());
        Assert.Equal(cancellationSource.Token, packageMetadataResource.ReceivedToken);
    }

    [Fact]
    public async Task VersionListsAreEnumeratedOncePerSourceAndPrereleaseOption()
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="source-one" value="https://one.example.com/v3/index.json" />
                    <add key="source-two" value="https://two.example.com/v3/index.json" />
                  </packageSources>
                </configuration>
                """)
        );
        var metadataResource = new CountingMetadataResource([
            NuGetVersion.Parse("1.0.0"),
            .. Enumerable.Range(1, 3_303)
                .Select(index => NuGetVersion.Parse($"2.0.0-preview.{index}")),
        ]);
        var cache = new PackageVersionsCache();

        for (var index = 0; index < 20; index++)
        {
            using var context = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
            var packageName = index % 2 == 0 ? "Some.Package" : "some.package";
            await GetVersionsWithNoCandidatesAsync(
                context,
                packageName,
                "1.0.0",
                TestContext.Current.CancellationToken);
            await GetVersionsWithNoCandidatesAsync(
                context,
                packageName,
                "1.0.0-beta",
                TestContext.Current.CancellationToken);
        }

        Assert.Equal(0, metadataResource.ExistsCallCount);
        Assert.Equal(4, metadataResource.GetVersionsCallCount);
    }

    [Fact]
    public async Task VersionListCacheIsScopedToTheNuGetConfigurationDirectory()
    {
        const string nugetConfig = """
            <configuration>
              <packageSources>
                <clear />
                <add key="source" value="https://example.com/v3/index.json" />
              </packageSources>
            </configuration>
            """;
        using var firstDirectory = await TemporaryDirectory.CreateWithContentsAsync(("NuGet.Config", nugetConfig));
        using var secondDirectory = await TemporaryDirectory.CreateWithContentsAsync(("NuGet.Config", nugetConfig));
        var metadataResource = new CountingMetadataResource([NuGetVersion.Parse("1.0.0")]);
        var cache = new PackageVersionsCache();

        using (var firstContext = CreateNuGetContext(firstDirectory.DirectoryPath, metadataResource, cache))
        {
            await GetVersionsWithNoCandidatesAsync(
                firstContext,
                "Some.Package",
                "1.0.0",
                TestContext.Current.CancellationToken);
        }

        using (var secondContext = CreateNuGetContext(secondDirectory.DirectoryPath, metadataResource, cache))
        {
            await GetVersionsWithNoCandidatesAsync(
                secondContext,
                "Some.Package",
                "1.0.0",
                TestContext.Current.CancellationToken);
        }

        Assert.Equal(2, metadataResource.GetVersionsCallCount);
    }

    [Fact]
    public async Task FailedVersionEnumerationsAreNotCached()
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="source" value="https://example.com/v3/index.json" />
                  </packageSources>
                </configuration>
                """)
        );
        var metadataResource = new CountingMetadataResource(
            [NuGetVersion.Parse("1.0.0")],
            failuresBeforeSuccess: 1);
        var cache = new PackageVersionsCache();

        using var context = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
        var firstResult = await GetVersionsWithNoCandidatesAsync(
            context,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);
        var secondResult = await GetVersionsWithNoCandidatesAsync(
            context,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);
        var thirdResult = await GetVersionsWithNoCandidatesAsync(
            context,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);

        Assert.Empty(firstResult.GetVersions());
        Assert.Empty(secondResult.GetVersions());
        Assert.Empty(thirdResult.GetVersions());
        Assert.Equal(2, metadataResource.GetVersionsCallCount);
    }

    [Fact]
    public async Task CanceledVersionEnumerationIsEvictedAndRetried()
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="source" value="https://example.com/v3/index.json" />
                  </packageSources>
                </configuration>
                """)
        );
        var metadataResource = new CancelThenSucceedMetadataResource([NuGetVersion.Parse("1.0.0")]);
        var cache = new PackageVersionsCache();

        using var context = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
        using var cancellationSource = CancellationTokenSource.CreateLinkedTokenSource(
            TestContext.Current.CancellationToken);
        var canceledResult = GetVersionsWithNoCandidatesAsync(
            context,
            "Some.Package",
            "1.0.0",
            cancellationSource.Token);
        await metadataResource.FirstRequestStarted.Task.WaitAsync(TestContext.Current.CancellationToken);
        await cancellationSource.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => canceledResult);
        var retryResult = await GetVersionsWithNoCandidatesAsync(
            context,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);

        Assert.Empty(retryResult.GetVersions());
        Assert.Equal(2, metadataResource.GetVersionsCallCount);
    }

    [Fact]
    public async Task CancelingConcurrentWaiterDoesNotEvictSharedVersionEnumeration()
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="source" value="https://example.com/v3/index.json" />
                  </packageSources>
                </configuration>
                """)
        );
        var metadataResource = new BlockingMetadataResource();
        var cache = new PackageVersionsCache();

        using var firstContext = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
        var firstResult = GetVersionsWithNoCandidatesAsync(
            firstContext,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);
        await metadataResource.RequestStarted.Task.WaitAsync(TestContext.Current.CancellationToken);

        using var secondContext = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
        using var cancellationSource = CancellationTokenSource.CreateLinkedTokenSource(
            TestContext.Current.CancellationToken);
        var canceledWaiter = GetVersionsWithNoCandidatesAsync(
            secondContext,
            "Some.Package",
            "1.0.0",
            cancellationSource.Token);
        await Task.Yield();
        await cancellationSource.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => canceledWaiter);
        metadataResource.Versions.SetResult([NuGetVersion.Parse("1.0.0")]);
        await firstResult;

        using var thirdContext = CreateNuGetContext(tempDir.DirectoryPath, metadataResource, cache);
        await GetVersionsWithNoCandidatesAsync(
            thirdContext,
            "Some.Package",
            "1.0.0",
            TestContext.Current.CancellationToken);

        Assert.Equal(1, metadataResource.GetVersionsCallCount);
    }

    private static NuGetContext CreateNuGetContext(
        string currentDirectory,
        MetadataResource metadataResource,
        PackageVersionsCache cache)
    {
        return new NuGetContext(
            currentDirectory,
            sourceRepositoryFactory: source => new SourceRepository(
                source,
                [new TestResourceProvider<MetadataResource>(metadataResource)]),
            packageVersionsCache: cache);
    }

    private static Task<VersionResult> GetVersionsWithNoCandidatesAsync(
        NuGetContext context,
        string packageName,
        string currentVersion,
        CancellationToken cancellationToken = default)
    {
        var dependencyInfo = new DependencyInfo
        {
            Name = packageName,
            Version = currentVersion,
            IsVulnerable = false,
        };

        return VersionFinder.GetVersionsAsync(
            projectTfms: [],
            dependencyInfo,
            NuGetVersion.Parse(currentVersion),
            versionFilter: _ => false,
            DateTimeOffset.UtcNow,
            context,
            new TestLogger(),
            cancellationToken);
    }

    private sealed class TestResourceProvider<TResource>(TResource resource) : INuGetResourceProvider
        where TResource : class, INuGetResource
    {
        public Type ResourceType => typeof(TResource);
        public string Name => typeof(TResource).Name;
        public IEnumerable<string> Before => [];
        public IEnumerable<string> After => [];

        public Task<Tuple<bool, INuGetResource?>> TryCreate(SourceRepository source, CancellationToken token) =>
            Task.FromResult(Tuple.Create(true, (INuGetResource?)resource));
    }

    private sealed class CountingMetadataResource(
        IEnumerable<NuGetVersion> versions,
        int failuresBeforeSuccess = 0) : MetadataResource
    {
        public int ExistsCallCount { get; private set; }
        public int GetVersionsCallCount { get; private set; }

        public override Task<bool> Exists(
            PackageIdentity identity,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            ExistsCallCount++;
            throw new InvalidOperationException("VersionFinder should not perform a separate existence check.");
        }

        public override Task<bool> Exists(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            ExistsCallCount++;
            throw new InvalidOperationException("VersionFinder should not perform a separate existence check.");
        }

        public override Task<IEnumerable<NuGetVersion>> GetVersions(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            GetVersionsCallCount++;
            if (GetVersionsCallCount <= failuresBeforeSuccess)
            {
                throw new InvalidDataException("Simulated feed failure.");
            }

            return Task.FromResult(versions);
        }

        public override Task<IEnumerable<KeyValuePair<string, NuGetVersion>>> GetLatestVersions(
            IEnumerable<string> packageIds,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) =>
            Task.FromResult<IEnumerable<KeyValuePair<string, NuGetVersion>>>([]);
    }

    private sealed class CancelThenSucceedMetadataResource(IEnumerable<NuGetVersion> versions) : MetadataResource
    {
        public TaskCompletionSource FirstRequestStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int GetVersionsCallCount { get; private set; }

        public override Task<bool> Exists(
            PackageIdentity identity,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();

        public override Task<bool> Exists(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();

        public override async Task<IEnumerable<NuGetVersion>> GetVersions(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            GetVersionsCallCount++;
            if (GetVersionsCallCount == 1)
            {
                FirstRequestStarted.SetResult();
                await Task.Delay(Timeout.Infinite, token);
            }

            return versions;
        }

        public override Task<IEnumerable<KeyValuePair<string, NuGetVersion>>> GetLatestVersions(
            IEnumerable<string> packageIds,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();
    }

    private sealed class BlockingMetadataResource : MetadataResource
    {
        public TaskCompletionSource RequestStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource<IEnumerable<NuGetVersion>> Versions { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int GetVersionsCallCount { get; private set; }

        public override Task<bool> Exists(
            PackageIdentity identity,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();

        public override Task<bool> Exists(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();

        public override Task<IEnumerable<NuGetVersion>> GetVersions(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            GetVersionsCallCount++;
            RequestStarted.SetResult();
            return Versions.Task;
        }

        public override Task<IEnumerable<KeyValuePair<string, NuGetVersion>>> GetLatestVersions(
            IEnumerable<string> packageIds,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();
    }

    private sealed class CapturingPackageMetadataResource : PackageMetadataResource
    {
        public CancellationToken ReceivedToken { get; private set; }

        public override Task<IEnumerable<IPackageSearchMetadata>> GetMetadataAsync(
            string packageId,
            bool includePrerelease,
            bool includeUnlisted,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token) => throw new NotImplementedException();

        public override Task<IPackageSearchMetadata> GetMetadataAsync(
            PackageIdentity package,
            SourceCacheContext sourceCacheContext,
            NuGet.Common.ILogger log,
            CancellationToken token)
        {
            ReceivedToken = token;
            return Task.FromResult<IPackageSearchMetadata>(
                new PackageSearchMetadataBuilder.ClonedPackageSearchMetadata
                {
                    Identity = package,
                    Published = DateTimeOffset.UtcNow.AddDays(-1),
                });
        }
    }
}
