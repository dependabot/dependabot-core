using System.Linq;
using System.Text;
using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class PackageReference : UpdateWorkerTestBase
    {
        [Fact]
        public async Task PartialUpdate_InMultipleProjectFiles_ForVersionConstraint()
        {
            // update Some.Package from 12.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="12.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    (Path: "src/Project/Project.csproj", Content: """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[12.0.1, 13.0.0)" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    (Path: "src/Project/Project.csproj", Content: """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[12.0.1, 13.0.0)" />
                          </ItemGroup>
                        </Project>
                        """),
                ]);
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceInclude_Windows()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    // necessary for the `net8.0-windows10.0.19041.0` TFM
                    MockNuGetPackage.WellKnownWindowsSdkRefPackage("10.0.19041.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
                        <RuntimeIdentifier>win-x64</RuntimeIdentifier>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
                        <RuntimeIdentifier>win-x64</RuntimeIdentifier>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InMultipleProjectFiles_ForPackageReferenceInclude()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <ProjectReference Include="lib\Library.csproj" />
                      </ItemGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("lib/Library.csproj", $"""
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <ProjectReference Include="lib\Library.csproj" />
                      </ItemGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("lib/Library.csproj", $"""
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task AddPackageReference_InProjectFile_ForTransientDependency(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };
            // add transient package Some.Transient.Dependency from 5.0.1 to 5.0.2
            await TestUpdateForProject("Some.Transient.Dependency", "5.0.1", "5.0.2", isTransitive: true,
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.1.3", "net8.0", [(null, [("Some.Transient.Dependency", "5.0.1")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transient.Dependency", "5.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transient.Dependency", "5.0.2", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.1.3" />
                      </ItemGroup>

                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.1.3" />
                        <PackageReference Include="Some.Transient.Dependency" Version="5.0.2" />
                      </ItemGroup>

                    </Project>
                    """
            );
        }

        [Fact]
        public async Task TransitiveDependencyCanBeAddedWithMismatchingSdk()
        {
            await TestUpdateForProject("Some.Transitive.Package", "1.0.0", "1.0.1", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Some.Transitive.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "99.99.999" // this version doesn't match anything that's installed
                          }
                        }
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                        <PackageReference Include="Some.Transitive.Package" Version="1.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task TransitiveDependencyCanBeAddedWithCustomMSBuildSdk()
        {
            await TestUpdateForProject("Some.Transitive.Package", "1.0.0", "1.0.1", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Some.Transitive.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.1", "net8.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Custom.MSBuild.Sdk", "1.2.3"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Sdk.props" Sdk="Custom.MSBuild.Sdk" />
                        </Project>
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "99.99.999" // this version doesn't match anything that's installed
                          },
                          "msbuild-sdks": {
                            "Custom.MSBuild.Sdk": "1.2.3"
                          }
                        }
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Some.Transitive.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Transitive.Package" Version="1.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForAnalyzerPackageReferenceInclude()
        {
            // update Some.Analyzer from 3.3.0 to 3.3.4
            await TestUpdateForProject("Some.Analyzer", "3.3.0", "3.3.4",
                packages:
                [
                    MockNuGetPackage.CreateAnalyzerPackage("Some.Analyzer", "3.3.0"),
                    MockNuGetPackage.CreateAnalyzerPackage("Some.Analyzer", "3.3.4"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Analyzer" Version="3.3.0">
                          <PrivateAssets>all</PrivateAssets>
                          <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Analyzer" Version="3.3.4">
                          <PrivateAssets>all</PrivateAssets>
                          <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForMultiplePackageReferences()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.PACKAGE" Version="9.0.1" />
                        <PackageReference Update="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.PACKAGE" Version="13.0.1" />
                        <PackageReference Update="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceUpdate()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceUpdateWithSemicolon()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package2", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package2", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InDirectoryPackages_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InDirectoryProps_ForGlobalPackageReference()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InDirectoryProps_ForGlobalPackageReference()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task LegacyProjectWithPackageReferencesCanUpdate()
        {
            await TestUpdateForProject("Some.Dependency", "1.0.0", "1.0.1",
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net48"),
                    MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.1", "net48"),
                ],
                projectContents: """
                    <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <OutputType>Library</OutputType>
                        <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <OutputType>Library</OutputType>
                        <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.1" />
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateDependencyWhenUnrelatedDependencyHasWildcardVersion()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "1.0.1",
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net9.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net9.0"),
                    MockNuGetPackage.CreateSimplePackage("Unrelated.Package", "2.1.0", "net9.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                        <PackageReference Include="Unrelated.Package" Version="2.*" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.1" />
                        <PackageReference Include="Unrelated.Package" Version="2.*" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }
    }
}
