using System.Text;
using System.Text.Json;
using System.Xml.Linq;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

using TestFile = (string Path, string Content);

public class RunWorkerTests
{
    [Fact]
    public async Task UpdateSinglePackageProducedExpectedAPIMessages()
    {
        var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package" />""");
        await RunAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repoMetadata]),
            ],
            job: new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir",
                },
                AllowedUpdates =
                [
                    new() { UpdateType = "all" }
                ]
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
                            """))
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
                    CommitMessage = "TODO: message",
                    PrTitle = "TODO: title",
                    PrBody = "TODO: body",
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    [Fact]
    public async Task PrivateSourceAuthenticationFailureIsForwaredToApiHandler()
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
                },
                AllowedUpdates =
                [
                    new() { UpdateType = "all" }
                ]
            },
            files:
            [
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
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
            expectedResult: new RunResult()
            {
                Base64DependencyFiles = [],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new PrivateSourceAuthenticationFailure([$"{http.BaseUrl.TrimEnd('/')}/index.json"]),
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
                },
                AllowedUpdates =
                [
                    new() { UpdateType = "all" }
                ]
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
                            """))
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "packages.config",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                            </packages>
                            """))
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
                            Version = "2.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.0",
                                    File = "/some-dir/packages.config",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/some-dir/project.csproj", "/some-dir/packages.config"],
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
                                    File = "/some-dir/packages.config",
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
                                    File = "/some-dir/packages.config",
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
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = "TODO: message",
                    PrTitle = "TODO: title",
                    PrBody = "TODO: body",
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
                },
                AllowedUpdates =
                [
                    new() { UpdateType = "all" }
                ]
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
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
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
                            """))
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
                            """))
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
                            """))
                    },
                    new DependencyFile()
                    {
                        Directory = "/some-dir/ProjectA",
                        Name = "packages.config",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <?xml version="1.0" encoding="utf-8"?>
                            <packages>
                              <package id="Some.Package2" version="2.0.0" targetFramework="net8.0" />
                            </packages>
                            """))
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
                                    File = "/some-dir/ProjectB/packages.config",
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
                                    File = "/some-dir/ProjectA/packages.config",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = ["/some-dir/ProjectB/ProjectB.csproj", "/some-dir/ProjectA/ProjectA.csproj", "/some-dir/ProjectB/packages.config", "/some-dir/ProjectA/packages.config"],
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
                                    File = "/some-dir/ProjectB/packages.config",
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
                                    File = "/some-dir/ProjectB/packages.config",
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
                            Name = "Some.Package2",
                            Version = "2.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "2.0.1",
                                    File = "/some-dir/ProjectA/packages.config",
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
                                    File = "/some-dir/ProjectA/packages.config",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "../ProjectB/ProjectB.csproj",
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
                        new DependencyFile()
                        {
                            Name = "../ProjectB/packages.config",
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
                            Directory = "/some-dir/ProjectA",
                            Content = """
                                <?xml version="1.0" encoding="utf-8"?>
                                <packages>
                                  <package id="Some.Package2" version="2.0.1" targetFramework="net8.0" />
                                </packages>
                                """,
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = "TODO: message",
                    PrTitle = "TODO: title",
                    PrBody = "TODO: body",
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }

    private static async Task RunAsync(Job job, TestFile[] files, RunResult? expectedResult, object[] expectedApiMessages, MockNuGetPackage[]? packages = null, string? repoContentsPath = null)
    {
        // arrange
        using var tempDirectory = new TemporaryDirectory();
        repoContentsPath ??= tempDirectory.DirectoryPath;
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, repoContentsPath);
        foreach (var (path, content) in files)
        {
            var fullPath = Path.Combine(repoContentsPath, path);
            var directory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(directory);
            await File.WriteAllTextAsync(fullPath, content);
        }

        // act
        var testApiHandler = new TestApiHandler();
        var worker = new RunWorker(testApiHandler, new TestLogger());
        var repoContentsPathDirectoryInfo = new DirectoryInfo(repoContentsPath);
        var actualResult = await worker.RunAsync(job, repoContentsPathDirectoryInfo, "TEST-COMMIT-SHA");
        var actualApiMessages = testApiHandler.ReceivedMessages.ToArray();

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
