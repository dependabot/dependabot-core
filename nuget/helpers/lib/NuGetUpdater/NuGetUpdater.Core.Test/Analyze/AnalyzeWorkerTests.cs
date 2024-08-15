using System.Text;
using System.Text.Json;

using NuGet;

using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public partial class AnalyzeWorkerTests : AnalyzeWorkerTestBase
{
    [Fact]
    public async Task FindsUpdatedVersion()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.0", "net8.0"), // `IgnoredVersions` should prevent this from being selected
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [Requirement.Parse("> 1.1.0")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.1.0",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Some.Package", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task FindsUpdatedPeerDependencies()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "4.0.1", DependencyType.PackageReference),
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.9.2",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Some.Package", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Some.Transitive.Dependency", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task DeterminesMultiPropertyVersion()
    {
        var evaluationResult = new EvaluationResult(EvaluationResultType.Success, "$(SomePackageVersion)", "4.0.1", "SomePackageVersion", ErrorMessage: null);
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                    new()
                    {
                        FilePath = "./project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Transitive.Dependency",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.9.2",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = true,
                UpdatedDependencies = [
                    new("Some.Package", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Some.Transitive.Dependency", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task FailsToUpdateMultiPropertyVersion()
    {
        // Package.A and Package.B happen to share some versions but would fail to update in sync with each other.
        var evaluationResult = new EvaluationResult(EvaluationResultType.Success, "$(TestPackageVersion)", "4.5.0", "TestPackageVersion", ErrorMessage: null);
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Package.A", "4.5.0", "net8.0"), // initial package versions match, purely by accident
                MockNuGetPackage.CreateSimplePackage("Package.A", "4.9.2", "net8.0"), // subsequent versions do not match
                MockNuGetPackage.CreateSimplePackage("Package.A", "4.9.3", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.2", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Package.A", "4.5.0", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                    new()
                    {
                        FilePath = "./project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Package.B", "4.5.0", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Package.A",
                Version = "4.5.0",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.5.0",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = true,
                UpdatedDependencies = [],
            }
        );
    }


    [Fact]
    public async Task ReturnsUpToDate_ForMissingVersionProperty()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "$(MissingPackageVersion)", DependencyType.PackageReference, EvaluationResult: new EvaluationResult(EvaluationResultType.PropertyNotFound, "$(MissingPackageVersion)", "$(MissingPackageVersion)", "$(MissingPackageVersion)", ErrorMessage: null)),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "$(MissingPackageVersion)",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "$(MissingPackageVersion)",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [],
            }
        );
    }

    [Fact]
    public async Task ReturnsUpToDate_ForMissingDependency()
    {
        await TestAnalyzeAsync(
            packages:
            [
                // no packages listed
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference), // this was found in the source, but doesn't exist in any feed
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.0.0",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [],
            }
        );
    }

    [Fact]
    public async Task ReturnsUpToDate_ForIgnoredRequirements()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.0.1",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [],
            }
        );
    }

    [Fact]
    public async Task AnalyzeVulnerableTransitiveDependencies()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "1.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "1.0.1", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
                        ]
                    }
                ]
            },
            dependencyInfo: new()
            {
                Name = "Some.Transitive.Dependency",
                Version = "1.0.0",
                IsVulnerable = true,
                IgnoredVersions = [],
                Vulnerabilities = [
                    new()
                    {
                        DependencyName = "Some.Transitive.Dependency",
                        PackageManager = "nuget",
                        VulnerableVersions = [Requirement.Parse("<= 1.0.0")],
                        SafeVersions = [Requirement.Parse("= 1.0.1")],
                    }
                ]
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.0.1",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Some.Transitive.Dependency", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task IgnoredVersionsCanHandleWildcardSpecification()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.0", "net8.0"), // `IgnoredVersions` should prevent this from being selected
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [Requirement.Parse("> 1.1.*")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.1.0",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Some.Package", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task VersionFinderCanHandle404FromPackageSource_V2()
    {
        static (int, byte[]) TestHttpHandler1(string uriString)
        {
            // this is a valid nuget package source, but doesn't contain anything
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                "/api/v2/" => (200, Encoding.UTF8.GetBytes($"""
                    <service xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom" xml:base="{baseUrl}/api/v2">
                        <workspace>
                            <atom:title type="text">Default</atom:title>
                            <collection href="Packages">
                                <atom:title type="text">Packages</atom:title>
                            </collection>
                        </workspace>
                    </service>
                    """)),
                _ => (404, Encoding.UTF8.GetBytes("{}")), // nothing else is found
            };
        }
        var desktopAppRefPackage = MockNuGetPackage.WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net8.0");
        (int, byte[]) TestHttpHandler2(string uriString)
        {
            // this contains the actual package
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            switch (uri.PathAndQuery)
            {
                case "/api/v2/":
                    return (200, Encoding.UTF8.GetBytes($"""
                        <service xmlns="http://www.w3.org/2007/app" xmlns:atom="http://www.w3.org/2005/Atom" xml:base="{baseUrl}/api/v2">
                            <workspace>
                                <atom:title type="text">Default</atom:title>
                                <collection href="Packages">
                                    <atom:title type="text">Packages</atom:title>
                                </collection>
                            </workspace>
                        </service>
                        """));
                case "/api/v2/FindPackagesById()?id='Some.Package'&semVerLevel=2.0.0":
                    return (200, Encoding.UTF8.GetBytes($"""
                        <feed xml:base="{baseUrl}/api/v2" xmlns="http://www.w3.org/2005/Atom"
                            xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
                            xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
                            xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
                            <m:count>2</m:count>
                            <id>http://schemas.datacontract.org/2004/07/</id>
                            <title />
                            <updated>{DateTime.UtcNow:O}</updated>
                            <link rel="self" href="{baseUrl}/api/v2/Packages" />
                            <entry>
                                <id>{baseUrl}/api/v2/Packages(Id='Some.Package',Version='1.0.0')</id>
                                <content type="application/zip" src="{baseUrl}/api/v2/package/Some.Package/1.0.0" />
                                <m:properties>
                                    <d:Version>1.0.0</d:Version>
                                </m:properties>
                            </entry>
                            <entry>
                                <id>{baseUrl}/api/v2/Packages(Id='Some.Package',Version='1.2.3')</id>
                                <content type="application/zip" src="{baseUrl}/api/v2/package/Some.Package/1.2.3" />
                                <m:properties>
                                    <d:Version>1.2.3</d:Version>
                                </m:properties>
                            </entry>
                        </feed>
                        """));
                case "/api/v2/Packages(Id='Some.Package',Version='1.2.3')":
                    return (200, Encoding.UTF8.GetBytes($"""
                        <entry xml:base="{baseUrl}/api/v2" xmlns="http://www.w3.org/2005/Atom"
                            xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
                            xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
                            xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
                            <id>{baseUrl}/api/v2/Packages(Id='Some.Package',Version='1.2.3')</id>
                            <updated>{DateTime.UtcNow:O}</updated>
                            <content type="application/zip" src="{baseUrl}/api/v2/package/Some.Package/1.2.3" />
                            <m:properties>
                                <d:Version>1.2.3</d:Version>
                            </m:properties>
                        </entry>
                        """));
                case "/api/v2/package/Some.Package/1.0.0":
                    return (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0").GetZipStream().ReadAllBytes());
                case "/api/v2/package/Some.Package/1.2.3":
                    return (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0").GetZipStream().ReadAllBytes());
                case "/api/v2/FindPackagesById()?id='Microsoft.WindowsDesktop.App.Ref'&semVerLevel=2.0.0":
                    return (200, Encoding.UTF8.GetBytes($"""
                        <feed xml:base="{baseUrl}/api/v2" xmlns="http://www.w3.org/2005/Atom"
                            xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices"
                            xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata"
                            xmlns:georss="http://www.georss.org/georss" xmlns:gml="http://www.opengis.net/gml">
                            <m:count>1</m:count>
                            <id>http://schemas.datacontract.org/2004/07/</id>
                            <title />
                            <updated>{DateTime.UtcNow:O}</updated>
                            <link rel="self" href="{baseUrl}/api/v2/Packages" />
                            <entry>
                                <id>{baseUrl}/api/v2/Packages(Id='Microsoft.WindowsDesktop.App.Ref',Version='{desktopAppRefPackage.Version}')</id>
                                <content type="application/zip" src="{baseUrl}/api/v2/package/Microsoft.WindowsDesktop.App.Ref/{desktopAppRefPackage.Version}" />
                                <m:properties>
                                    <d:Version>{desktopAppRefPackage.Version}</d:Version>
                                </m:properties>
                            </entry>
                        </feed>
                        """));
                default:
                    if (uri.PathAndQuery == $"/api/v2/package/Microsoft.WindowsDesktop.App.Ref/{desktopAppRefPackage.Version}")
                    {
                        return (200, desktopAppRefPackage.GetZipStream().ReadAllBytes());
                    }

                    // nothing else is found
                    return (404, Encoding.UTF8.GetBytes("{}"));
            };
        }
        using var http1 = TestHttpServer.CreateTestServer(TestHttpHandler1);
        using var http2 = TestHttpServer.CreateTestServer(TestHttpHandler2);
        await TestAnalyzeAsync(
            extraFiles:
            [
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="package_feed_1" value="{http1.BaseUrl.TrimEnd('/')}/api/v2/" allowInsecureConnections="true" />
                        <add key="package_feed_2" value="{http2.BaseUrl.TrimEnd('/')}/api/v2/" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ],
            discovery: new()
            {
                Path = "/",
                Projects =
                [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies =
                        [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference),
                        ]
                    }
                ]
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.2.3",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies =
                [
                    new("Some.Package", "1.2.3", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task VersionFinderCanHandle404FromPackageSource_V3()
    {
        static (int, byte[]) TestHttpHandler1(string uriString)
        {
            // this is a valid nuget package source, but doesn't contain anything
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                "/index.json" => (200, Encoding.UTF8.GetBytes($$"""
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
                    """)),
                _ => (404, Encoding.UTF8.GetBytes("{}")), // nothing else is found
            };
        }
        var desktopAppRefPackage = MockNuGetPackage.WellKnownReferencePackage("Microsoft.WindowsDesktop.App", "net8.0");
        (int, byte[]) TestHttpHandler2(string uriString)
        {
            // this contains the actual package
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            switch (uri.PathAndQuery)
            {
                case "/index.json":
                    return (200, Encoding.UTF8.GetBytes($$"""
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
                        """));
                case "/registrations/some.package/index.json":
                    return (200, Encoding.UTF8.GetBytes("""
                        {
                            "count": 1,
                            "items": [
                                {
                                    "lower": "1.0.0",
                                    "upper": "1.2.3",
                                    "items": [
                                        {
                                            "catalogEntry": {
                                                "listed": true,
                                                "version": "1.0.0"
                                            }
                                        },
                                        {
                                            "catalogEntry": {
                                                "listed": true,
                                                "version": "1.2.3"
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                        """));
                case "/download/some.package/index.json":
                    return (200, Encoding.UTF8.GetBytes("""
                        {
                            "versions": [
                                "1.0.0",
                                "1.2.3"
                            ]
                        }
                        """));
                case "/download/microsoft.windowsdesktop.app.ref/index.json":
                    return (200, Encoding.UTF8.GetBytes($$"""
                        {
                            "versions": [
                                "{{desktopAppRefPackage.Version}}"
                            ]
                        }
                        """));
                case "/download/some.package/1.0.0/some.package.1.0.0.nupkg":
                    return (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0").GetZipStream().ReadAllBytes());
                case "/download/some.package/1.2.3/some.package.1.2.3.nupkg":
                    return (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0").GetZipStream().ReadAllBytes());
                default:
                    if (uri.PathAndQuery == $"/download/microsoft.windowsdesktop.app.ref/{desktopAppRefPackage.Version}/microsoft.windowsdesktop.app.ref.{desktopAppRefPackage.Version}.nupkg")
                    {
                        return (200, desktopAppRefPackage.GetZipStream().ReadAllBytes());
                    }

                    // nothing else is found
                    return (404, Encoding.UTF8.GetBytes("{}"));
            };
        }
        using var http1 = TestHttpServer.CreateTestServer(TestHttpHandler1);
        using var http2 = TestHttpServer.CreateTestServer(TestHttpHandler2);
        await TestAnalyzeAsync(
            extraFiles:
            [
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="package_feed_1" value="{http1.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                        <add key="package_feed_2" value="{http2.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ],
            discovery: new()
            {
                Path = "/",
                Projects =
                [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies =
                        [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference),
                        ]
                    }
                ]
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.2.3",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies =
                [
                    new("Some.Package", "1.2.3", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task ResultFileHasCorrectShapeForAuthenticationFailure()
    {
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync([]);
        await AnalyzeWorker.WriteResultsAsync(temporaryDirectory.DirectoryPath, "Some.Dependency", new()
        {
            ErrorType = ErrorType.AuthenticationFailure,
            ErrorDetails = "<some package feed>",
            UpdatedVersion = "",
            UpdatedDependencies = [],
        }, new Logger(false));
        var discoveryContents = await File.ReadAllTextAsync(Path.Combine(temporaryDirectory.DirectoryPath, "Some.Dependency.json"));

        // raw result file should look like this:
        // {
        //   ...
        //   "ErrorType": "AuthenticationFailure",
        //   "ErrorDetails": "<some package feed>",
        //   ...
        // }
        var jsonDocument = JsonDocument.Parse(discoveryContents);
        var errorType = jsonDocument.RootElement.GetProperty("ErrorType");
        var errorDetails = jsonDocument.RootElement.GetProperty("ErrorDetails");

        Assert.Equal("AuthenticationFailure", errorType.GetString());
        Assert.Equal("<some package feed>", errorDetails.GetString());
    }

    [Fact]
    public async Task ReportsPrivateSourceAuthenticationFailure()
    {
        static (int, string) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                // initial request is good
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
                // all other requests are unauthorized
                _ => (401, "{}"),
            };
        }
        using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
        await TestAnalyzeAsync(
            extraFiles:
            [
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.2.3", DependencyType.PackageReference),
                        ],
                    }
                ]
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.2.3",
                IgnoredVersions = [],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                ErrorType = ErrorType.AuthenticationFailure,
                ErrorDetails = $"({http.BaseUrl.TrimEnd('/')}/index.json)",
                UpdatedVersion = string.Empty,
                CanUpdate = false,
                UpdatedDependencies = [],
            }
        );
    }
}
