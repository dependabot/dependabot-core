using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class PackagesConfig : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net46"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net46"),
                ],
                workspacePath: "",
                files: [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.A" version="1.0.0" targetFramework="net46" />
                          <package id="Package.B" version="2.0.0" targetFramework="net46" />
                        </packages>
                        """),
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [
                                new("TargetFramework", "net46", "myproj.csproj")
                            ],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Package.B", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task DiscoversDependencies_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net46"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net46"),
                ],
                workspacePath: "",
                files: [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.A" version="1.0.0" targetFramework="net46" />
                          <package id="Package.B" version="2.0.0" targetFramework="net46" />
                        </packages>
                        """),
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [new("TargetFramework", "net46", "myproj.csproj")],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Package.B", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ],
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task DiscoveryIsMergedWithPackageReferences(bool useDirectDiscovery)
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net46"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net46"),
                ],
                workspacePath: "src",
                files: [
                    ("src/myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="..\unexpected-directory\packages.config" />
                            <PackageReference Include="Package.B" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("unexpected-directory/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.A" version="1.0.0" targetFramework="net46" />
                        </packages>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "src",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [new("TargetFramework", "net46", "src/myproj.csproj")],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Package.B", "2.0.0", DependencyType.PackageReference, IsDirect: true, TargetFrameworks: ["net46"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "../unexpected-directory/packages.config"
                            ],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task DirectDiscoveryWorksEvenWithTargetsImportsOnlyProvidedByVisualStudio()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net48"),
                ],
                files: [
                    ("project.csproj", """
                        <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <OutputType>Library</OutputType>
                            <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <Import Project="$(VSToolsPath)\SomeSubPath\WebApplications\Microsoft.WebApplication.targets" />
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Some.Package" version="1.0.0" targetFramework="net48" />
                        </packages>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Properties = [],
                            TargetFrameworks = ["net48"],
                            Dependencies = [
                                new("Some.Package", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net48"]),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ]
                }
            );
        }
    }
}
