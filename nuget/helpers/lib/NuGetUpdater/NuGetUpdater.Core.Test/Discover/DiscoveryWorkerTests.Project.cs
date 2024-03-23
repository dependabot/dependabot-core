using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class Projects : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task ReturnsPackageReferencesMissingVersions()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <Description>Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.</Description>
                            <TargetFrameworks>netstandard1.6;net462</TargetFrameworks>
                          </PropertyGroup>

                          <ItemGroup>
                            <EmbeddedResource Include="ErrorHandling\Resources\**\*.*;Diagnostics\Resources\**\*.*;Diagnostics\Views\**\*.*" Exclude="bin\**;obj\**;**\*.xproj;packages\**;@(EmbeddedResource)" />
                          </ItemGroup>

                          <ItemGroup Condition=" '$(TargetFramework)' == 'netstandard1.6' ">
                            <PackageReference Include="Microsoft.Extensions.DependencyModel" Version="1.1.1" />
                            <PackageReference Include="Microsoft.AspNetCore.App" />
                            <PackageReference Include="Microsoft.NET.Test.Sdk" Version="" />
                            <PackageReference Include="Microsoft.Extensions.PlatformAbstractions" version="1.1.0"></PackageReference>
                            <PackageReference Include="System.Collections.Specialized"><Version>4.3.0</Version></PackageReference>
                          </ItemGroup>

                          <ItemGroup Condition=" '$(TargetFramework)' == 'net462' ">
                            <Reference Include="System.Xml" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    FilePath = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            ExpectedDependencyCount = 52,
                            Dependencies = [
                                new("Microsoft.Extensions.DependencyModel", "1.1.1", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.AspNetCore.App", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.NET.Test.Sdk", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                                new("Microsoft.Extensions.PlatformAbstractions", "1.1.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("System.Collections.Specialized", "4.3.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                            ],
                            Properties = [
                                new("Description", "Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.", "myproj.csproj"),
                                new("TargetFrameworks", "netstandard1.6;net462", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net462", "netstandard1.6"],
                            ReferencedProjectPaths = [],
                        }
                    ],
                });
        }

        [Fact]
        public async Task WithDirectoryPackagesProps()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <Description>Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.</Description>
                            <TargetFrameworks>netstandard1.6;net462</TargetFrameworks>
                          </PropertyGroup>

                          <ItemGroup>
                            <EmbeddedResource Include="ErrorHandling\Resources\**\*.*;Diagnostics\Resources\**\*.*;Diagnostics\Views\**\*.*" Exclude="bin\**;obj\**;**\*.xproj;packages\**;@(EmbeddedResource)" />
                          </ItemGroup>

                          <ItemGroup Condition=" '$(TargetFramework)' == 'netstandard1.6' ">
                            <PackageReference Include="Microsoft.Extensions.DependencyModel" Version="1.1.1" />
                            <PackageReference Include="Microsoft.AspNetCore.App" />
                            <PackageReference Include="Microsoft.NET.Test.Sdk" Version="" />
                            <PackageReference Include="Microsoft.Extensions.PlatformAbstractions" version="1.1.0"></PackageReference>
                            <PackageReference Include="System.Collections.Specialized"><Version>4.3.0</Version></PackageReference>
                          </ItemGroup>

                          <ItemGroup Condition=" '$(TargetFramework)' == 'net462' ">
                            <Reference Include="System.Xml" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("directory.packages.props", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="System.Lycos" Version="3.23.3" />
                            <PackageVersion Include="System.AskJeeves" Version="2.2.2" />
                            <PackageVersion Include="System.Google" Version="0.1.0-beta.3" />
                            <PackageVersion Include="System.WebCrawler" Version="1.1.1" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    FilePath = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            ExpectedDependencyCount = 52,
                            Dependencies = [
                                new("Microsoft.Extensions.DependencyModel", "1.1.1", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.AspNetCore.App", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.NET.Test.Sdk", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                                new("Microsoft.Extensions.PlatformAbstractions", "1.1.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                new("System.Collections.Specialized", "4.3.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                            ],
                            Properties = [
                                new("Description", "Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.", "myproj.csproj"),
                                new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                                new("TargetFrameworks", "netstandard1.6;net462", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net462", "netstandard1.6"],
                        },
                    ],
                    DirectoryPackagesProps = new()
                    {
                        FilePath = "Directory.Packages.props",
                        Dependencies = [
                            new("System.Lycos", "3.23.3", DependencyType.PackageVersion, IsDirect: true),
                            new("System.AskJeeves", "2.2.2", DependencyType.PackageVersion, IsDirect: true),
                            new("System.Google", "0.1.0-beta.3", DependencyType.PackageVersion, IsDirect: true),
                            new("System.WebCrawler", "1.1.1", DependencyType.PackageVersion, IsDirect: true),
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                        ],
                    },
                });
        }

        [Fact]
        public async Task WithPackagesProps()
        {
            var nugetPackagesDirectory = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
            var nugetHttpCacheDirectory = Environment.GetEnvironmentVariable("NUGET_HTTP_CACHE_PATH");

            try
            {
                using var temp = new TemporaryDirectory();

                // It is important to have empty NuGet caches for this test, so override them with temp directories.
                var tempNuGetPackagesDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "packages");
                Environment.SetEnvironmentVariable("NUGET_PACKAGES", tempNuGetPackagesDirectory);
                var tempNuGetHttpCacheDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "v3-cache");
                Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", tempNuGetHttpCacheDirectory);

                await TestDiscoveryAsync(
                    workspacePath: "",
                    files: [
                        ("myproj.csproj", """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <Description>Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.</Description>
                                <TargetFrameworks>netstandard1.6;net462</TargetFrameworks>
                              </PropertyGroup>

                              <ItemGroup>
                                <EmbeddedResource Include="ErrorHandling\Resources\**\*.*;Diagnostics\Resources\**\*.*;Diagnostics\Views\**\*.*" Exclude="bin\**;obj\**;**\*.xproj;packages\**;@(EmbeddedResource)" />
                              </ItemGroup>

                              <ItemGroup Condition=" '$(TargetFramework)' == 'netstandard1.6' ">
                                <PackageReference Include="Microsoft.Extensions.DependencyModel" Version="1.1.1" />
                                <PackageReference Include="Microsoft.AspNetCore.App" />
                                <PackageReference Include="Microsoft.NET.Test.Sdk" Version="" />
                                <PackageReference Include="Microsoft.Extensions.PlatformAbstractions" version="1.1.0"></PackageReference>
                                <PackageReference Include="System.Collections.Specialized"><Version>4.3.0</Version></PackageReference>
                              </ItemGroup>

                              <ItemGroup Condition=" '$(TargetFramework)' == 'net462' ">
                                <Reference Include="System.Xml" />
                              </ItemGroup>
                            </Project>
                            """),
                        ("packages.props", """
                            <Project Sdk="Microsoft.NET.Sdk">
                              <ItemGroup>
                                <GlobalPackageReference Include="Microsoft.SourceLink.GitHub" Version="1.0.0-beta2-19367-01" />
                                <PackageReference Update="@(GlobalPackageReference)" PrivateAssets="Build" />
                                <PackageReference Update="System.Lycos" Version="3.23.3" />
                                <PackageReference Update="System.AskJeeves" Version="2.2.2" />
                                <PackageReference Update="System.Google" Version="0.1.0-beta.3" />
                                <PackageReference Update="System.WebCrawler" Version="1.1.1" />
                              </ItemGroup>
                            </Project>
                            """),
                        ("Directory.Build.targets", """
                            <Project>
                              <Sdk Name="Microsoft.Build.CentralPackageVersions" Version="2.1.3" />
                            </Project>
                            """),
                    ],
                    expectedResult: new()
                    {
                        FilePath = "",
                        ExpectedProjectCount = 3,
                        Projects = [
                            new()
                            {
                                FilePath = "myproj.csproj",
                                ExpectedDependencyCount = 52,
                                Dependencies = [
                                    new("Microsoft.Extensions.DependencyModel", "1.1.1", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                    new("Microsoft.AspNetCore.App", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                    new("Microsoft.NET.Test.Sdk", "", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                    new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                                    new("Microsoft.Extensions.PlatformAbstractions", "1.1.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                    new("System.Collections.Specialized", "4.3.0", DependencyType.PackageReference, TargetFrameworks: ["net462", "netstandard1.6"], IsDirect: true),
                                ],
                                Properties = [
                                    new("Description", "Nancy is a lightweight web framework for the .Net platform, inspired by Sinatra. Nancy aim at delivering a low ceremony approach to building light, fast web applications.", "myproj.csproj"),
                                    new("TargetFrameworks", "netstandard1.6;net462", "myproj.csproj"),
                                ],
                                TargetFrameworks = ["net462", "netstandard1.6"],
                            },
                            new()
                            {
                                FilePath = "Packages.props",
                                Dependencies = [
                                    new("Microsoft.SourceLink.GitHub", "1.0.0-beta2-19367-01", DependencyType.GlobalPackageReference, IsDirect: true),
                                    new("System.Lycos", "3.23.3", DependencyType.PackageReference, IsDirect: true, IsUpdate: true),
                                    new("System.AskJeeves", "2.2.2", DependencyType.PackageReference, IsDirect: true, IsUpdate: true),
                                    new("System.Google", "0.1.0-beta.3", DependencyType.PackageReference, IsDirect: true, IsUpdate: true),
                                    new("System.WebCrawler", "1.1.1", DependencyType.PackageReference, IsDirect: true, IsUpdate: true),
                                    new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                                ],
                            },
                        ],
                    });
            }
            finally
            {
                // Restore the NuGet caches.
                Environment.SetEnvironmentVariable("NUGET_PACKAGES", nugetPackagesDirectory);
                Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", nugetHttpCacheDirectory);
            }
        }

        [Fact]
        public async Task ReturnsDependenciesThatCannotBeEvaluated()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                            <PackageReference Include="Package.B" Version="$(ThisPropertyCannotBeResolved)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    FilePath = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Package.B", "$(ThisPropertyCannotBeResolved)", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                        }
                    ],
                });
        }
    }
}
