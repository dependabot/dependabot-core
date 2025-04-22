using System.Text;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run;
using Xunit;
using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Test.Run;

public class EndToEndTests
{
    [Fact]
    public async Task UpdatePackageWithDifferentVersionsInDifferentDirectories()
    {
        // this test passes `null` for discovery, analyze, and update workers to fully test the desired behavior

        // the same dependency Some.Package is reported for 3 cases:
        //   library1.csproj - top level dependency, already up to date
        //   library2.csproj - top level dependency, needs direct update
        //   library3.csproj - transitive dependency, needs pin
        await RunWorkerTests.RunAsync(
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.With.Transitive.Dependency", "0.1.0", "net8.0", [(null, [("Some.Package", "1.0.0")])]),
            ],
            job: new Job()
            {
                AllowedUpdates = [new() { UpdateType = UpdateType.Security }],
                SecurityAdvisories =
                [
                    new()
                    {
                        DependencyName = "Some.Package",
                        AffectedVersions = [Requirement.Parse("= 1.0.0")]
                    }
                ],
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/"
                }
            },
            files: [
                ("dirs.proj", """
                    <Project>
                      <ItemGroup>
                        <ProjectFile Include="library1\library1.csproj" />
                        <ProjectFile Include="library2\library2.csproj" />
                        <ProjectFile Include="library3\library3.csproj" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Build.props", "<Project />"),
                ("Directory.Build.targets", "<Project />"),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                    </Project>
                    """),
                ("library1/library1.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("library2/library2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("library3/library3.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.With.Transitive.Dependency" Version="0.1.0" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            discoveryWorker: null,
            analyzeWorker: null,
            updaterWorker: null,
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/",
                        Name = "Directory.Build.props",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("<Project />")),
                        ContentEncoding = "base64",
                    },
                    new DependencyFile()
                    {
                        Directory = "/",
                        Name = "Directory.Build.targets",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("<Project />")),
                        ContentEncoding = "base64",
                    },
                    new DependencyFile()
                    {
                        Directory = "/",
                        Name = "Directory.Packages.props",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project>
                              <PropertyGroup>
                                <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                              </PropertyGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64",
                    },
                    new DependencyFile()
                    {
                        Directory = "/library1",
                        Name = "library1.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="2.0.0" />
                              </ItemGroup>
                            </Project>
                            """)),
                        ContentEncoding = "base64",
                    },
                    new DependencyFile()
                    {
                        Directory = "/library2",
                        Name = "library2.csproj",
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
                        ContentEncoding = "base64",
                    },
                    new DependencyFile()
                    {
                        Directory = "/library3",
                        Name = "library3.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Package.With.Transitive.Dependency" Version="0.1.0" />
                              </ItemGroup>
                            </Project>
                            """)),
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
                            Name = "Some.Package",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/library1/library1.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/library2/library2.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Package.With.Transitive.Dependency",
                            Version = "0.1.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "0.1.0",
                                    File = "/library3/library3.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/library3/library3.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = [
                        "/Directory.Build.props",
                        "/Directory.Build.targets",
                        "/Directory.Packages.props",
                        "/library1/library1.csproj",
                        "/library2/library2.csproj",
                        "/library3/library3.csproj",
                    ],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "create_security_pr"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Package",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/library2/library2.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/library2/library2.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                        new()
                        {
                            Name = "Some.Package",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/library3/library3.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/library3/library3.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/library2",
                            Name = "library2.csproj",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="2.0.0" />
                                  </ItemGroup>
                                </Project>
                                """
                        },
                        new()
                        {
                            Directory = "/library3",
                            Name = "library3.csproj",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Package.With.Transitive.Dependency" Version="0.1.0" />
                                    <PackageReference Include="Some.Package" Version="2.0.0" />
                                  </ItemGroup>
                                </Project>
                                """
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }
}
