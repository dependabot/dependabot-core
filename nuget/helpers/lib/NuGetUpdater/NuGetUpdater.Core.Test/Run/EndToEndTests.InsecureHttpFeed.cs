using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

using TestFile = (string Path, string Content);

public class EndToEndTests_InsecureHttpFeed
{
    [Fact]
    public async Task UpdatesPackagesFromInsecureHttpFeed_WithSlnxAndMixedProjectTypes()
    {
        // Verifies that packages can be discovered and updated from insecure HTTP feeds without
        // explicitly setting allowInsecureConnections in the NuGet.Config file. The RunWorker
        // automatically patches NuGet.Config files to add this attribute for http:// sources.
        // Uses a V3 feed for the SDK-style project and a V2 feed for the packages.config project.
        using var httpV3 = TestHttpServer.CreateTestNuGetFeed(
            MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Package.A", "1.1.0", "net9.0")
        );

        using var httpV2 = TestHttpServer.CreateTestNuGetV2Feed(
            MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net45"),
            MockNuGetPackage.CreateSimplePackage("Package.B", "2.1.0", "net45")
        );

        await EndToEndTests.RunAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Package.A", "1.1.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "2.1.0", "net45"),
            ],
            job: new()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "/",
                }
            },
            files: [
                ("Directory.Build.props", "<Project />"),
                ("Directory.Build.targets", "<Project />"),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                    </Project>
                    """),
                ("repo.slnx", """
                    <Solution>
                      <Project Path="src\project-a\project-a.csproj" />
                      <Project Path="src\project-b\project-b.csproj" />
                    </Solution>
                    """),
                ("src/project-a/project-a.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/project-a/NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <add key="test_v3_feed" value="{httpV3.GetPackageFeedIndex()}" />
                      </packageSources>
                    </configuration>
                    """),
                ("src/project-b/project-b.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Package.B">
                          <HintPath>packages\Package.B.2.0.0\lib\net45\Package.B.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("src/project-b/packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Package.B" version="2.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("src/project-b/NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <add key="test_v2_feed" value="{httpV2.GetV2FeedUrl()}" />
                      </packageSources>
                    </configuration>
                    """),
            ],
            discoveryWorker: null,
            analyzeWorker: null,
            updaterWorker: null,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.A",
                            Version = "1.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.0.0",
                                    File = "/src/project-a/project-a.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                        new()
                        {
                            Name = "Package.B",
                            Version = "2.0.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/src/project-b/project-b.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        },
                    ],
                    DependencyFiles = [
                        "/Directory.Build.props",
                        "/Directory.Build.targets",
                        "/Directory.Packages.props",
                        "/src/project-a/project-a.csproj",
                        "/src/project-b/packages.config",
                        "/src/project-b/project-b.csproj",
                    ],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.A",
                            Version = "1.1.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "1.1.0",
                                    File = "/src/project-a/project-a.csproj",
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
                                    File = "/src/project-a/project-a.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src/project-a",
                            Name = "project-a.csproj",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net9.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Package.A" Version="1.1.0" />
                                  </ItemGroup>
                                </Project>
                                """
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.B",
                            Version = "2.1.0",
                            Requirements = [
                                new()
                                {
                                    Requirement = "2.1.0",
                                    File = "/src/project-b/project-b.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = null,
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "2.0.0",
                            PreviousRequirements = [
                                new()
                                {
                                    Requirement = "2.0.0",
                                    File = "/src/project-b/project-b.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src/project-b",
                            Name = "packages.config",
                            Content = """
                                <?xml version="1.0" encoding="utf-8"?>
                                <packages>
                                  <package id="Package.B" version="2.1.0" targetFramework="net45" />
                                </packages>
                                """
                        },
                        new()
                        {
                            Directory = "/src/project-b",
                            Name = "project-b.csproj",
                            Content = """
                                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                                  <PropertyGroup>
                                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <None Include="packages.config" />
                                  </ItemGroup>
                                  <ItemGroup>
                                    <Reference Include="Package.B">
                                      <HintPath>packages\Package.B.2.1.0\lib\net45\Package.B.dll</HintPath>
                                      <Private>True</Private>
                                    </Reference>
                                  </ItemGroup>
                                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                                </Project>
                                """
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA")
            ]
        );
    }
}
