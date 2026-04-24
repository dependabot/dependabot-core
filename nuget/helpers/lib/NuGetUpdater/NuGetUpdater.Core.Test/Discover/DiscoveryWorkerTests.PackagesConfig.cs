using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class PackagesConfig : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies()
        {
            await TestDiscoveryAsync(
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
        public async Task DiscoveryIsMergedWithPackageReferences()
        {
            await TestDiscoveryAsync(
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
        public async Task AttemptedSDKDiscoveryDoesNotInvokeBuild()
        {
            // Ensure the `Build` target (which eventually calls `CoreCompile`) isn't invoked when detecting SDK-style packages
            // in a legacy project.  Doing that full invocation is usually harmless, but slow and it fills the log with red herrings.

            // To test this a legacy project is given a target with `BeforeTargets="CoreCompile"` which writes a sentinel file to disk
            // so we have to ensure that file doesn't get created.
            using var tempDir = new TemporaryDirectory();
            var sentinelFile = Path.Combine(tempDir.DirectoryPath, "sentinel.txt");

            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("PackageReferencedThroughLegacyMechanism", "1.0.0", "net48"),
                    MockNuGetPackage.CreateSimplePackage("PackageReferencedThroughCPMMechanism", "2.0.0", "net48"),
                ],
                workspacePath: "src",
                files: [
                    ("Directory.Build.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="PackageReferencedThroughCPMMechanism" />
                          </ItemGroup>
                        </Project>
                    """),
                    ("Directory.Build.targets", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagedPackageVersionsCentrally>true</ManagedPackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="PackageReferencedThroughCPMMechanism" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/myproj.csproj", $$"""
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="PackageReferencedThroughLegacyMechanism">
                              <HintPath>packages\PackageReferencedThroughLegacyMechanism.1.0.0\lib\net48\PackageReferencedThroughLegacyMechanism.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Target Name="PreCoreCompileSentinel" BeforeTargets="CoreCompile">
                            <WriteLinesToFile File="{{sentinelFile}}" Lines="CoreCompile target was called" Overwrite="true" />
                          </Target>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("src/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="PackageReferencedThroughLegacyMechanism" version="1.0.0" targetFramework="net48" />
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
                            TargetFrameworks = ["net48"],
                            Dependencies = [
                                new("PackageReferencedThroughLegacyMechanism", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net48"]),
                                new("PackageReferencedThroughCPMMechanism", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net48"], IsDirect: true),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "../Directory.Build.props",
                                "../Directory.Build.targets",
                                "../Directory.Packages.props"
                            ],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ],
                }
            );

            // Verify that the CoreCompile target was not called by checking that the sentinel file was not created
            Assert.False(File.Exists(sentinelFile), "CoreCompile target should not have been called during discovery");
        }

        [Fact]
        public async Task DiscoveryWorksEvenWithTargetsImportsOnlyProvidedByVisualStudio()
        {
            await TestDiscoveryAsync(
                workspacePath: "project1/",
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net48"),
                ],
                files: [
                    ("project1/project1.csproj", """
                        <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <OutputType>Library</OutputType>
                            <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <ProjectReference Include="..\project2\project2.csproj" />
                          </ItemGroup>
                          <Import Project="$(VSToolsPath)\SomeSubPath\WebApplications\Microsoft.WebApplication.targets" />
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("project1/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Some.Package" version="1.0.0" targetFramework="net48" />
                        </packages>
                        """),
                    ("project2/project2.csproj", """
                        <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <OutputType>Library</OutputType>
                            <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                          </PropertyGroup>
                          <Import Project="$(VSToolsPath)\SomeSubPath\WebApplications\Microsoft.WebApplication.targets" />
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "project1/",
                    Projects = [
                        new()
                        {
                            FilePath = "project1.csproj",
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
