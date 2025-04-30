using System.Net;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

using static NuGetUpdater.Core.Utilities.EOLHandling;

using TestFile = (string Path, string Content);
using RawTestFile = (string Path, byte[] Content);

public class RunWorkerTests
{
    public const string TestPullRequestCommitMessage = "test-pull-request-commit-message";
    public const string TestPullRequestTitle = "test-pull-request-title";
    public const string TestPullRequestBody = "test-pull-request-body";

    [Fact]
    public async Task UpdateSinglePackageProducedExpectedAPIMessages()
    {
        await RunAsync(
            packages: [],
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir",
                }
            },
            files:
            [
                ("some-dir/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "some-dir",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "project.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies =
                            [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                return Task.FromResult(new AnalysisResult()
                {
                    UpdatedVersion = "1.0.1",
                    CanUpdate = true,
                    UpdatedDependencies =
                    [
                        new("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package"),
                    ]
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                Assert.Equal("Some.Package", input.Item3);
                Assert.Equal("1.0.0", input.Item4);
                Assert.Equal("1.0.1", input.Item5);
                var projectPath = input.Item1 + input.Item2;
                await File.WriteAllTextAsync(projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.1" />
                      </ItemGroup>
                    </Project>
                    """);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = "Some.Package",
                            NewVersion = NuGetVersion.Parse("1.0.1"),
                            UpdatedFiles = ["/some-dir/project.csproj"]
                        }
                    ],
                };
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.0" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/some-dir/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        }
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "project.csproj",
                            Directory = "/some-dir",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="1.0.1" />
                                  </ItemGroup>
                                </Project>
                                """,
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task UpdateHandlesSemicolonsInPackageReference()
    {
        var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package" />""");
        var repoMetadata2 = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package2" />""");
        await RunAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "1.0.0", "net8.0", additionalMetadata: [repoMetadata2]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "1.0.1", "net8.0", additionalMetadata: [repoMetadata2]),
            ],
            job: new Job()
            {
                PackageManager = "nuget",
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir",
                }
            },
            files:
            [
                ("some-dir/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "some-dir",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "project.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies =
                            [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                                new("Some.Package2", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                return Task.FromResult(new AnalysisResult()
                {
                    UpdatedVersion = "1.0.1",
                    CanUpdate = true,
                    UpdatedDependencies =
                    [
                        new("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package"),
                        new("Some.Package2", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package2"),
                    ]
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                Assert.Contains(input.Item3, new List<string> { "Some.Package", "Some.Package2" });
                Assert.Equal("1.0.0", input.Item4);
                Assert.Equal("1.0.1", input.Item5);
                var projectPath = input.Item1 + input.Item2;
                await File.WriteAllTextAsync(projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="1.0.1" />
                      </ItemGroup>
                    </Project>
                    """);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = "Some.Package",
                            NewVersion = NuGetVersion.Parse("1.0.1"),
                            UpdatedFiles = ["/some-dir/project.csproj"]
                        },
                        new DirectUpdate()
                        {
                            DependencyName = "Some.Package2",
                            NewVersion = NuGetVersion.Parse("1.0.1"),
                            UpdatedFiles = ["/some-dir/project.csproj"]
                        }
                    ],
                };
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package;Some.Package2" Version="1.0.0" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = ["/some-dir/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package2",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "project.csproj",
                            Directory = "/some-dir",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package;Some.Package2" Version="1.0.1" />
                                  </ItemGroup>
                                </Project>
                                """,
                        }

                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task ErrorsFromDiscoveryWorkerAreForwaredToApiHandler()
    {
        await RunAsync(
            packages:
            [
            ],
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            files:
            [
                ("NuGet.Config", """
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="http://example.com/nuget/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker((_input) =>
            {
                throw new HttpRequestException(message: null, inner: null, statusCode: HttpStatusCode.Unauthorized);
            }),
            analyzeWorker: TestAnalyzeWorker.FromResults(),
            updaterWorker: TestUpdaterWorker.FromResults(),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new PrivateSourceAuthenticationFailure(["http://example.com/nuget/index.json"]),
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task ErrorsFromAnalyzeWorkerAreForwaredToApiHandler()
    {
        await RunAsync(
            packages:
            [
            ],
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            files:
            [
                ("NuGet.Config", """
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="http://example.com/nuget/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker((_input) =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"])],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker((_input) =>
            {
                throw new HttpRequestException(message: null, inner: null, statusCode: HttpStatusCode.Unauthorized);
            }),
            updaterWorker: TestUpdaterWorker.FromResults(),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new PrivateSourceAuthenticationFailure(["http://example.com/nuget/index.json"]),
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task ErrorsFromUpdaterWorkerAreForwaredToApiHandler()
    {
        await RunAsync(
            packages:
            [
            ],
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            files:
            [
                ("NuGet.Config", """
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="http://example.com/nuget/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker((_input) =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"])],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker((_input) =>
            {
                return Task.FromResult(new AnalysisResult()
                {
                    UpdatedVersion = "1.0.1",
                    CanUpdate = true,
                    UpdatedDependencies =
                    [
                        new("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package"),
                    ]
                });
            }),
            updaterWorker: new TestUpdaterWorker((_input) =>
            {
                throw new HttpRequestException(message: null, inner: null, statusCode: HttpStatusCode.Unauthorized);
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new PrivateSourceAuthenticationFailure(["http://example.com/nuget/index.json"]),
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task UpdateHandlesPackagesConfigFiles()
    {
        var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package" />""");
        var repoMetadata2 = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package2" />""");
        await RunAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "2.0.0", "net8.0", additionalMetadata: [repoMetadata2]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "2.0.1", "net8.0", additionalMetadata: [repoMetadata2]),
            ],
            job: new Job()
            {
                PackageManager = "nuget",
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir",
                }
            },
            files:
            [
                ("some-dir/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("some-dir/packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                    </packages>
                    """),
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "some-dir",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "project.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies =
                            [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                                new("Some.Package2", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = ["packages.config"],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var result = input.Item3.Name switch
                {
                    "Some.Package" => new AnalysisResult()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "1.0.1",
                        UpdatedDependencies =
                            [
                                new("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package"),
                            ]
                    },
                    "Some.Package2" => new AnalysisResult()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "2.0.1",
                        UpdatedDependencies =
                            [
                                new("Some.Package2", "2.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package2"),
                            ]
                    },
                    _ => throw new NotSupportedException(),
                };
                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRootPath = input.Item1;
                var filePath = input.Item2;
                var packageName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var _isTransitive = input.Item6;

                var projectPath = Path.Join(repoRootPath, filePath);
                switch (packageName)
                {
                    case "Some.Package":
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                             </Project>
                            """);
                        break;
                    case "Some.Package2":
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                              <ItemGroup>
                                <Reference Include="Some.Package2">
                                  <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                  <Private>True</Private>
                                </Reference>
                              </ItemGroup>
                            </Project>
                            """);
                        var packagesConfigPath = Path.Join(Path.GetDirectoryName(projectPath)!, "packages.config");
                        await File.WriteAllTextAsync(packagesConfigPath, """
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                            </packages>
                            """);
                        break;
                    default:
                        throw new NotSupportedException();
                }

                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = packageName,
                            NewVersion = NuGetVersion.Parse(newVersion),
                            UpdatedFiles = [filePath]
                        }
                    ],
                };
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "packages.config",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                            </packages>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.0" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/some-dir/packages.config", "/some-dir/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package2",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "packages.config",
                            Directory = "/some-dir",
                            Content = """
                                <?xml version="1.0" encoding="utf-8"?>
                                <packages>
                                  <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                                </packages>
                                """,
                        },
                        new DependencyFile()
                        {
                            Name = "project.csproj",
                            Directory = "/some-dir",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="1.0.1" />
                                  </ItemGroup>
                                  <ItemGroup>
                                    <Reference Include="Some.Package2">
                                      <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                      <Private>True</Private>
                                    </Reference>
                                  </ItemGroup>
                                </Project>
                                """,
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task UpdateHandlesPackagesConfigFromReferencedCsprojFiles()
    {
        var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package" />""");
        var repoMetadata2 = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package2" />""");
        await RunAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "2.0.0", "net8.0", additionalMetadata: [repoMetadata2]),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "2.0.1", "net8.0", additionalMetadata: [repoMetadata2]),
            ],
            job: new Job()
            {
                PackageManager = "nuget",
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir/ProjectA",
                }
            },
            files:
            [
                ("some-dir/ProjectA/ProjectA.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                      <ItemGroup>
                        <ProjectReference Include="../ProjectB/ProjectB.csproj" />
                      </ItemGroup>
                    </Project>
                    """),
                ("some-dir/ProjectA/packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                    </packages>
                    """),
                ("some-dir/ProjectB/ProjectB.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("some-dir/ProjectB/packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                    </packages>
                    """),
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "some-dir/ProjectA",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "../ProjectB/ProjectB.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies =
                            [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                                new("Some.Package2", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = ["packages.config"],
                        },
                        new()
                        {
                            FilePath = "ProjectA.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies =
                            [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                                new("Some.Package2", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = ["packages.config"],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var result = input.Item3.Name switch
                {
                    "Some.Package" => new AnalysisResult()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "1.0.1",
                        UpdatedDependencies =
                            [
                                new("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package"),
                            ]
                    },
                    "Some.Package2" => new AnalysisResult()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "2.0.1",
                        UpdatedDependencies =
                            [
                                new("Some.Package2", "2.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some-package2"),
                            ]
                    },
                    _ => throw new NotSupportedException(),
                };
                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRootPath = input.Item1;
                var filePath = input.Item2;
                var packageName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var _isTransitive = input.Item6;

                var projectPath = Path.Join(repoRootPath, filePath);
                var projectName = Path.GetFileName(projectPath);
                var packagesConfigPath = Path.Join(Path.GetDirectoryName(projectPath)!, "packages.config");
                switch ((projectName, packageName))
                {
                    case ("ProjectA.csproj", "Some.Package"):
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                              <ItemGroup>
                                <ProjectReference Include="../ProjectB/ProjectB.csproj" />
                              </ItemGroup>
                            </Project>
                            """);
                        break;
                    case ("ProjectA.csproj", "Some.Package2"):
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                              <ItemGroup>
                                <ProjectReference Include="../ProjectB/ProjectB.csproj" />
                              </ItemGroup>
                              <ItemGroup>
                                <Reference Include="Some.Package2">
                                  <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                  <Private>True</Private>
                                </Reference>
                              </ItemGroup>
                            </Project>
                            """);
                        await File.WriteAllTextAsync(packagesConfigPath, """
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                            </packages>
                            """);
                        break;
                    case ("ProjectB.csproj", "Some.Package"):
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                            </Project>
                            """);
                        break;
                    case ("ProjectB.csproj", "Some.Package2"):
                        await File.WriteAllTextAsync(projectPath, """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.1" />
                              </ItemGroup>
                              <ItemGroup>
                                <Reference Include="Some.Package2">
                                  <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                  <Private>True</Private>
                                </Reference>
                              </ItemGroup>
                            </Project>
                            """);
                        await File.WriteAllTextAsync(packagesConfigPath, """
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                            </packages>
                            """);
                        break;
                    default:
                        throw new NotSupportedException();
                }

                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = packageName,
                            NewVersion = NuGetVersion.Parse(newVersion),
                            UpdatedFiles = [filePath]
                        }
                    ],
                };
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/some-dir/ProjectA",
                        Name = "packages.config",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                            </packages>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir/ProjectA",
                        Name = "ProjectA.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.0" />
                              </ItemGroup>
                              <ItemGroup>
                                <ProjectReference Include="../ProjectB/ProjectB.csproj" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir/ProjectB",
                        Name = "packages.config",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                            </packages>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir/ProjectB",
                        Name = "ProjectB.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.0" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = ["/some-dir/ProjectA/packages.config", "/some-dir/ProjectA/ProjectA.csproj", "/some-dir/ProjectB/packages.config", "/some-dir/ProjectB/ProjectB.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package2",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/ProjectA/ProjectA.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package2",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/ProjectB/ProjectB.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "packages.config",
                            Directory = "/some-dir/ProjectA",
                            Content = """
                                <?xml version="1.0" encoding="utf-8"?>
                                <packages>
                                  <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                                </packages>
                                """,
                        },
                        new DependencyFile()
                        {
                            Name = "ProjectA.csproj",
                            Directory = "/some-dir/ProjectA",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="1.0.1" />
                                  </ItemGroup>
                                  <ItemGroup>
                                    <ProjectReference Include="../ProjectB/ProjectB.csproj" />
                                  </ItemGroup>
                                  <ItemGroup>
                                    <Reference Include="Some.Package2">
                                      <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                      <Private>True</Private>
                                    </Reference>
                                  </ItemGroup>
                                </Project>
                                """,
                        },
                        new DependencyFile()
                        {
                            Name = "packages.config",
                            Directory = "/some-dir/ProjectB",
                            Content = """
                                <?xml version="1.0" encoding="utf-8"?>
                                <packages>
                                  <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                                </packages>
                                """,
                        },
                        new DependencyFile()
                        {
                            Name = "ProjectB.csproj",
                            Directory = "/some-dir/ProjectB",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="1.0.1" />
                                  </ItemGroup>
                                  <ItemGroup>
                                    <Reference Include="Some.Package2">
                                      <HintPath>..\packages\Some.Package2.2.0.1\lib\net8.0\Some.Package2.dll</HintPath>
                                      <Private>True</Private>
                                    </Reference>
                                  </ItemGroup>
                                </Project>
                                """,
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task UpdatedFilesAreOnlyReportedOnce()
    {
        await RunAsync(
            job: new()
            {
                PackageManager = "nuget",
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"),
            ],
            files:
            [
                ("dirs.proj", """
                    <Project>
                      <ItemGroup>
                        <ProjectFile Include="project1/project1.csproj" />
                        <ProjectFile Include="project2/project2.csproj" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <SomePackageVersion>1.0.0</SomePackageVersion>
                      </PropertyGroup>
                    </Project>
                    """),
                ("project1/project1.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                ("project2/project2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project1/project1.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies = [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "../Directory.Build.props",
                            ],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "project2/project2.csproj",
                            TargetFrameworks = ["net8.0"],
                            Dependencies = [
                                new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "../Directory.Build.props",
                            ],
                            AdditionalFiles = [],
                        },
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(_input =>
            {
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = "1.1.0",
                    UpdatedDependencies =
                        [
                            new("Some.Package", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                        ]
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRootPath = input.Item1;
                var filePath = input.Item2;
                var packageName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var _isTransitive = input.Item6;

                var directoryBuildPropsPath = Path.Join(repoRootPath, "Directory.Build.props");
                await File.WriteAllTextAsync(directoryBuildPropsPath, """
                    <Project>
                      <PropertyGroup>
                        <SomePackageVersion>1.1.0</SomePackageVersion>
                      </PropertyGroup>
                    </Project>
                    """);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = packageName,
                            NewVersion = NuGetVersion.Parse(newVersion),
                            UpdatedFiles = [filePath]
                        }
                    ],
                };
            }),
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/",
                        Name = "Directory.Build.props",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project>
                              <PropertyGroup>
                                <SomePackageVersion>1.0.0</SomePackageVersion>
                              </PropertyGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/project1",
                        Name = "project1.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                    new DependencyFile()
                    {
                        Directory = "/project2",
                        Name = "project2.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64"
                    },
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project1/project1.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project2/project2.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/Directory.Build.props", "/project1/project1.csproj", "/project2/project2.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.1.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.1.0",
                                    File = "/project1/project1.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project1/project1.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.1.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.1.0",
                                    File = "/project2/project2.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/project2/project2.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "Directory.Build.props",
                            Directory = "/",
                            Content = """
                                <Project>
                                  <PropertyGroup>
                                    <SomePackageVersion>1.1.0</SomePackageVersion>
                                  </PropertyGroup>
                                </Project>
                                """,
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task PackageListedInSecurityAdvisoriesSectionIsNotVulnerable()
    {
        await RunAsync(
            job: new()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                SecurityUpdatesOnly = true,
                SecurityAdvisories = [
                    new()
                    {
                        DependencyName = "Package.Is.Not.Vulnerable",
                        AffectedVersions = [Requirement.Parse("< 1.0.0")]
                    }
                ]
            },
            files: [
                ("project.csproj", "contents irrelevant")
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Package.Is.Not.Vulnerable", "1.0.1", DependencyType.PackageReference)
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(_input => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(_input => throw new NotImplementedException("test shouldn't get this far")),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("contents irrelevant")),
                        ContentEncoding = "base64"
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.Is.Not.Vulnerable",
                            Version = "1.0.1",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.1",
                                    File = "/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/project.csproj"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "create_security_pr"
                    }
                },
                new SecurityUpdateNotNeeded("Package.Is.Not.Vulnerable"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task PackageListedInSecurityAdvisoriesSectionIsNotPresent()
    {
        await RunAsync(
            job: new()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                SecurityUpdatesOnly = true,
                SecurityAdvisories = [
                    new()
                    {
                        DependencyName = "Package.Is.Not.Vulnerable",
                        AffectedVersions = [Requirement.Parse("< 1.0.0")]
                    }
                ]
            },
            files: [
                ("project.csproj", "contents irrelevant")
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Unrelated.Package", "0.1.0", DependencyType.PackageReference)
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(_input => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(_input => throw new NotImplementedException("test shouldn't get this far")),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("contents irrelevant")),
                        ContentEncoding = "base64"
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Unrelated.Package",
                            Version = "0.1.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "0.1.0",
                                    File = "/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/project.csproj"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "create_security_pr"
                    }
                },
                new SecurityUpdateNotNeeded("Package.Is.Not.Vulnerable"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task NonProjectFilesAreIncludedInPullRequest()
    {
        await RunAsync(
            job: new()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
            },
            files: [
                (".config/dotnet-tools.json", "dotnet-tools.json content old"),
                ("global.json", "global.json content old")
            ],
            discoveryWorker: new TestDiscoveryWorker(input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [],
                    DotNetToolsJson = new()
                    {
                        FilePath = ".config/dotnet-tools.json",
                        Dependencies = [
                            new("some-tool", "2.0.0", DependencyType.DotNetTool),
                        ]
                    },
                    GlobalJson = new()
                    {
                        FilePath = "global.json",
                        Dependencies = [
                            new("Some.MSBuild.Sdk", "1.0.0", DependencyType.MSBuildSdk),
                        ],
                    },
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var (_repoRoot, _discoveryResult, dependencyInfo) = input;
                var result = dependencyInfo.Name switch
                {
                    "some-tool" => new AnalysisResult() { CanUpdate = true, UpdatedVersion = "2.0.1", UpdatedDependencies = [new("some-tool", "2.0.1", DependencyType.DotNetTool)] },
                    "Some.MSBuild.Sdk" => new AnalysisResult() { CanUpdate = true, UpdatedVersion = "1.0.1", UpdatedDependencies = [new("Some.MSBuild.Sdk", "1.0.1", DependencyType.MSBuildSdk)] },
                    _ => throw new NotImplementedException("unreachable")
                };
                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var (repoRoot, filePath, dependencyName, _previousVersion, newVersion, _isTransitive) = input;
                var dependencyFilePath = Path.Join(repoRoot, filePath);
                var updatedContent = dependencyName switch
                {
                    "some-tool" => "dotnet-tools.json content UPDATED",
                    "Some.MSBuild.Sdk" => "global.json content UPDATED",
                    _ => throw new NotImplementedException("unreachable")
                };
                await File.WriteAllTextAsync(dependencyFilePath, updatedContent);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = dependencyName,
                            NewVersion = NuGetVersion.Parse(newVersion),
                            UpdatedFiles = [filePath]
                        }
                    ],
                };
            }),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/.config",
                        Name = "dotnet-tools.json",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("dotnet-tools.json content old")),
                        ContentEncoding = "base64"
                    },
                    new()
                    {
                        Directory = "/",
                        Name = "global.json",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("global.json content old")),
                        ContentEncoding = "base64"
                    },
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "some-tool",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/.config/dotnet-tools.json",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Some.MSBuild.Sdk",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/global.json",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = ["/.config/dotnet-tools.json", "/global.json"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "some-tool",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/.config/dotnet-tools.json",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                    }
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/.config/dotnet-tools.json",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Some.MSBuild.Sdk",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/global.json",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/global.json",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "dotnet-tools.json",
                            Directory = "/.config",
                            Content = "dotnet-tools.json content UPDATED",
                        },
                        new DependencyFile()
                        {
                            Name = "global.json",
                            Directory = "/",
                            Content = "global.json content UPDATED",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task PullRequestAlreadyExistsForLatestVersion()
    {
        await RunAsync(
            job: new()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                Dependencies = [
                    "Some.Package"
                ],
                ExistingPullRequests = [
                    new PullRequest()
                    {
                        Dependencies = [new() { DependencyName = "Some.Package", DependencyVersion = NuGetVersion.Parse("1.2.0") }]
                    }
                ],
                SecurityAdvisories = [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("= 1.1.0")] }
                ],
                SecurityUpdatesOnly = true,
                UpdatingAPullRequest = false
            },
            files: [
                ("project.csproj", "contents irrelevant")
            ],
            discoveryWorker: new TestDiscoveryWorker(_input =>
            {
                return Task.FromResult(new WorkspaceDiscoveryResult()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Package", "1.1.0", DependencyType.PackageReference)
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                });
            }),
            analyzeWorker: new TestAnalyzeWorker(_input =>
            {
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = "1.2.0",
                    UpdatedDependencies = [
                        new("Some.Package", "1.2.0", DependencyType.PackageReference)
                    ]
                });
            }),
            updaterWorker: new TestUpdaterWorker(input =>
            {
                throw new NotImplementedException("test should never get here");
            }),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("contents irrelevant")),
                        ContentEncoding = "base64"
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Package",
                            Version = "1.1.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.1.0",
                                    File = "/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/project.csproj"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "create_security_pr"
                    }
                },
                new PullRequestExistsForLatestVersion("Some.Package", "1.2.0"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task ByteOrderMarksAreDetectedAndRestored()
    {
        var rawBOM = Encoding.UTF8.GetPreamble();

        // file1 goes from BOM to no BOM
        var file1ContentOriginal = rawBOM.Concat(Encoding.ASCII.GetBytes("content1")).ToArray();
        var file1ContentUpdated = Encoding.ASCII.GetBytes("updated1");

        // file2 goes from no BOM to BOM
        var file2ContentOriginal = Encoding.ASCII.GetBytes("content2");
        var file2ContentUpdated = rawBOM.Concat(Encoding.ASCII.GetBytes("updated2")).ToArray();

        await RunAsync(
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            rawFiles:
            [
                ("file1", file1ContentOriginal),
                ("file2", file2ContentOriginal)
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(("/", new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "file1",
                        Dependencies = [new("Dependency1", "1.0.0", DependencyType.PackageReference)],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    },
                    new()
                    {
                        FilePath = "file2",
                        Dependencies = [new("Dependency2", "2.0.0", DependencyType.PackageReference)],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            })),
            analyzeWorker: new TestAnalyzeWorker(args =>
            {
                AnalysisResult result = args.Item3.Name switch
                {
                    "Dependency1" => new()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "1.0.1",
                        UpdatedDependencies = [new("Dependency1", "1.0.1", DependencyType.PackageReference)],
                    },
                    "Dependency2" => new()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "2.0.1",
                        UpdatedDependencies = [new("Dependency2", "2.0.1", DependencyType.PackageReference)],
                    },
                    _ => throw new NotImplementedException()
                };
                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async args =>
            {
                var (repoRoot, filePath, dependencyName, _previousVersion, _newVersion, _isTransitive) = args;

                // file1 is rewritten without BOM, file2 is rewritten with BOM
                var (updatedFileContent, newVersion) = dependencyName switch
                {
                    "Dependency1" => (file1ContentUpdated, "1.0.1"),
                    "Dependency2" => (file2ContentUpdated, "2.0.1"),
                    _ => throw new NotImplementedException(),
                };
                var fullFilePath = Path.Join(repoRoot, filePath);
                await File.WriteAllBytesAsync(fullFilePath, updatedFileContent);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate()
                    {
                        DependencyName = dependencyName,
                        NewVersion = NuGetVersion.Parse(newVersion),
                        UpdatedFiles = [filePath],
                    }],
                };
            }),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/",
                        Name = "file1",
                        Content = Convert.ToBase64String(file1ContentOriginal),
                        ContentEncoding = "base64",
                    },
                    new()
                    {
                        Directory = "/",
                        Name = "file2",
                        Content = Convert.ToBase64String(file2ContentOriginal),
                        ContentEncoding = "base64",
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Dependency1",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Dependency2",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/file2",
                                    Groups = ["dependencies"]
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/file1", "/file2"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Dependency1",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                    Source = new() { SourceUrl = null },
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Dependency2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/file2",
                                    Groups = ["dependencies"],
                                    Source = new() { SourceUrl = null },
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/file2",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        // original line endings have been restored
                        new DependencyFile()
                        {
                            Name = "file1",
                            Directory = "/",
                            Content = Convert.ToBase64String(rawBOM.Concat(file1ContentUpdated).ToArray()),
                            ContentEncoding = "base64",
                        },
                        new DependencyFile()
                        {
                            Name = "file2",
                            Directory = "/",
                            Content = "updated2",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task LineEndingsAreDetectedAndRestored()
    {
        await RunAsync(
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            files:
            [
                // initially LF
                ("file1", string.Concat(
                    "file1-line1\n",
                    "file1-line2\n",
                    "file1-line3\n"
                    )
                ),
                // initially CRLF
                ("file2", string.Concat(
                    "file2-line1\r\n",
                    "file2-line2\r\n",
                    "file2-line3\r\n"
                    )
                )
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(("/", new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "file1",
                        Dependencies = [new("Dependency1", "1.0.0", DependencyType.PackageReference)],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    },
                    new()
                    {
                        FilePath = "file2",
                        Dependencies = [new("Dependency2", "2.0.0", DependencyType.PackageReference)],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            })),
            analyzeWorker: new TestAnalyzeWorker(args =>
            {
                AnalysisResult result = args.Item3.Name switch
                {
                    "Dependency1" => new()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "1.0.1",
                        UpdatedDependencies = [new("Dependency1", "1.0.1", DependencyType.PackageReference)],
                    },
                    "Dependency2" => new()
                    {
                        CanUpdate = true,
                        UpdatedVersion = "2.0.1",
                        UpdatedDependencies = [new("Dependency2", "2.0.1", DependencyType.PackageReference)],
                    },
                    _ => throw new NotImplementedException()
                };
                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async args =>
            {
                var (repoRoot, filePath, dependencyName, _previousVersion, _newVersion, _isTransitive) = args;

                // file is explicitly updated with CR
                var (updatedFileContent, newVersion) = dependencyName switch
                {
                    "Dependency1" => (string.Concat(
                        "file1-line1-updated\r",
                        "file1-line2-updated\r",
                        "file1-line3-updated\r"), "1.0.1"),
                    "Dependency2" => (string.Concat(
                        "file2-line1-updated\r",
                        "file2-line2-updated\r",
                        "file2-line3-updated\r"), "2.0.1"),
                    _ => throw new NotImplementedException(),
                };
                var fullFilePath = Path.Join(repoRoot, filePath);
                await File.WriteAllTextAsync(fullFilePath, updatedFileContent);
                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate()
                    {
                        DependencyName = dependencyName,
                        NewVersion = NuGetVersion.Parse(newVersion),
                        UpdatedFiles = [filePath],
                    }],
                };
            }),
            expectedResult: new()
            {
                Base64DependencyFiles = [
                    new()
                    {
                        Directory = "/",
                        Name = "file1",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes(string.Concat(
                            "file1-line1\n",
                            "file1-line2\n",
                            "file1-line3\n"))),
                        ContentEncoding = "base64",
                    },
                    new()
                    {
                        Directory = "/",
                        Name = "file2",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes(string.Concat(
                            "file2-line1\r\n",
                            "file2-line2\r\n",
                            "file2-line3\r\n"))),
                        ContentEncoding = "base64",
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Dependency1",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Dependency2",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/file2",
                                    Groups = ["dependencies"]
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/file1", "/file2"]
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Dependency1",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                    Source = new() { SourceUrl = null },
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/file1",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new ReportedDependency()
                        {
                            Name = "Dependency2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/file2",
                                    Groups = ["dependencies"],
                                    Source = new() { SourceUrl = null },
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/file2",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        // original line endings have been restored
                        new DependencyFile()
                        {
                            Name = "file1",
                            Directory = "/",
                            Content = string.Concat(
                                "file1-line1-updated\n",
                                "file1-line2-updated\n",
                                "file1-line3-updated\n"
                            ),
                        },
                        new DependencyFile()
                        {
                            Name = "file2",
                            Directory = "/",
                            Content = string.Concat(
                                "file2-line1-updated\r\n",
                                "file2-line2-updated\r\n",
                                "file2-line3-updated\r\n"
                            ),
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = TestPullRequestCommitMessage,
                    PrTitle = TestPullRequestTitle,
                    PrBody = TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    internal static Task RunAsync(Job job, TestFile[] files, IDiscoveryWorker? discoveryWorker, IAnalyzeWorker? analyzeWorker, IUpdaterWorker? updaterWorker, RunResult expectedResult, object[] expectedApiMessages, MockNuGetPackage[]? packages = null, ExperimentsManager? experimentsManager = null, string? repoContentsPath = null)
    {
        var rawTestFiles = files.Select(f => (f.Path, Encoding.UTF8.GetBytes(f.Content))).ToArray();
        return RunAsync(job, rawTestFiles, discoveryWorker, analyzeWorker, updaterWorker, expectedResult, expectedApiMessages, packages, experimentsManager, repoContentsPath);
    }

    private static async Task RunAsync(Job job, RawTestFile[] rawFiles, IDiscoveryWorker? discoveryWorker, IAnalyzeWorker? analyzeWorker, IUpdaterWorker? updaterWorker, RunResult expectedResult, object[] expectedApiMessages, MockNuGetPackage[]? packages = null, ExperimentsManager? experimentsManager = null, string? repoContentsPath = null)
    {
        // arrange
        using var tempDirectory = new TemporaryDirectory();
        repoContentsPath ??= tempDirectory.DirectoryPath;
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, repoContentsPath);
        foreach (var (path, content) in rawFiles)
        {
            var fullPath = Path.Combine(repoContentsPath, path);
            var directory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(directory);
            await File.WriteAllBytesAsync(fullPath, content);
        }

        // act
        experimentsManager ??= new ExperimentsManager();
        var testApiHandler = new TestApiHandler();
        var logger = new TestLogger();
        var jobId = "TEST-JOB-ID";
        discoveryWorker ??= new DiscoveryWorker(jobId, experimentsManager, logger);
        analyzeWorker ??= new AnalyzeWorker(jobId, experimentsManager, logger);
        updaterWorker ??= new UpdaterWorker(jobId, experimentsManager, logger);

        var worker = new RunWorker(jobId, testApiHandler, discoveryWorker, analyzeWorker, updaterWorker, logger);
        var repoContentsPathDirectoryInfo = new DirectoryInfo(tempDirectory.DirectoryPath);
        var actualResult = await worker.RunAsync(job, repoContentsPathDirectoryInfo, "TEST-COMMIT-SHA");
        var actualApiMessages = testApiHandler.ReceivedMessages
            .Select(m =>
                m.Object switch
                {
                    // this isn't the place to verify the generated text
                    CreatePullRequest create => (m.Type, create with { CommitMessage = TestPullRequestCommitMessage, PrTitle = TestPullRequestTitle, PrBody = TestPullRequestBody }),
                    UpdatePullRequest update => (m.Type, update with { CommitMessage = TestPullRequestCommitMessage, PrTitle = TestPullRequestTitle, PrBody = TestPullRequestBody }),
                    _ => m,
                }
            ).ToArray();

        // assert
        var actualRunResultJson = JsonSerializer.Serialize(actualResult);
        var expectedRunResultJson = JsonSerializer.Serialize(expectedResult);
        Assert.Equal(expectedRunResultJson, actualRunResultJson);
        for (int i = 0; i < Math.Min(actualApiMessages.Length, expectedApiMessages.Length); i++)
        {
            var actualMessage = actualApiMessages[i];
            var expectedMessage = expectedApiMessages[i];
            Assert.Equal(expectedMessage.GetType(), actualMessage.Type);

            var expectedContent = SerializeObjectAndType(expectedMessage);
            var actualContent = SerializeObjectAndType(actualMessage.Object);
            Assert.Equal(expectedContent, actualContent);
        }

        if (actualApiMessages.Length > expectedApiMessages.Length)
        {
            var extraApiMessages = actualApiMessages.Skip(expectedApiMessages.Length).Select(m => SerializeObjectAndType(m.Object)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but got {extraApiMessages.Length} extra:\n\t{string.Join("\n\t", extraApiMessages)}");
        }
        if (expectedApiMessages.Length > actualApiMessages.Length)
        {
            var missingApiMessages = expectedApiMessages.Skip(actualApiMessages.Length).Select(m => SerializeObjectAndType(m)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but only got {actualApiMessages.Length}; missing:\n\t{string.Join("\n\t", missingApiMessages)}");
        }
    }

    internal static string SerializeObjectAndType(object obj)
    {
        return $"{obj.GetType().Name}:{JsonSerializer.Serialize(obj)}";
    }
}
