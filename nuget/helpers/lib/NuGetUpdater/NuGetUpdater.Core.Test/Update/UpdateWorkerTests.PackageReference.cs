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
        public async Task VersionAttributeWithDifferentCasing_VersionNumberInline()
        {
            // the version attribute in the project has an all lowercase name
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task VersionAttributeWithDifferentCasing_VersionNumberInProperty()
        {
            // the version attribute in the project has an all lowercase name
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.props" />
                        </Project>
                        """),
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>12.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // no change
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // no change
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.props" />
                        </Project>
                        """),
                    // version number was updated here
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>13.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task DirectoryPackagesPropsDoesCentralPackagePinningGetsUpdatedIfTransitiveFlagIsSet()
        {
            await TestUpdateForProject("Some.Package.Extensions", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.0.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.1.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                ],
                isTransitive: true,
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
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
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task DirectoryPackagesPropsDoesNotGetDuplicateEntryIfCentralTransitivePinningIsUsed()
        {
            await TestUpdateForProject("Some.Package.Extensions", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.0.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.1.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                ],
                isTransitive: true,
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task PackageWithFourPartVersionCanBeUpdated()
        {
            await TestUpdateForProject("Some.Package", "1.2.3.4", "1.2.3.5",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3.4", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3.5", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3.4" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3.5" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task PackageWithOnlyBuildTargetsCanBeUpdated()
        {
            await TestUpdateForProject("Some.Package", "7.0.0", "7.1.0",
                packages:
                [
                    new("Some.Package", "7.0.0", Files: [("buildTransitive/net7.0/_._", [])]),
                    new("Some.Package", "7.1.0", Files: [("buildTransitive/net7.0/_._", [])]),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.1.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageVersionFromPropertiesWithAndWithoutConditions()
        {
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(UseLegacyVersion7) == 'true'">7.0.1</SomePackageVersion>
                        <SomePackageVersion>12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(UseLegacyVersion7) == 'true'">7.0.1</SomePackageVersion>
                        <SomePackageVersion>13.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageVersionFromPropertyWithConditionCheckingForEmptyString()
        {
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(SomePackageVersion) == ''">12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(SomePackageVersion) == ''">13.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatingTransitiveDependencyWithNewSolverCanUpdateJustTheTopLevelPackage()
        {
            // we've been asked to explicitly update a transitive dependency, but we can solve it by updating the top-level package instead
            await TestUpdateForProject("Transitive.Package", "7.0.0", "8.0.0",
                isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [("net8.0", [("Transitive.Package", "[7.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0", [("net8.0", [("Transitive.Package", "[8.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "7.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "8.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedResult: new()
                {
                    UpdateOperations = [
                        new DirectUpdate()
                        {
                            DependencyName = "Some.Package",
                            NewVersion = NuGetVersion.Parse("2.0.0"),
                            UpdatedFiles = ["/src/test-project.csproj"]
                        },
                        new ParentUpdate()
                        {
                            DependencyName = "Transitive.Package",
                            NewVersion = NuGetVersion.Parse("8.0.0"),
                            UpdatedFiles = ["/src/test-project.csproj"],
                            ParentDependencyName = "Some.Package",
                            ParentNewVersion = NuGetVersion.Parse("2.0.0")
                        }
                    ]
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task NoChange_IfThereAreIncoherentVersions(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // trying to update `Transitive.Dependency` to 1.1.0 would normally pull `Some.Package` from 1.0.0 to 1.1.0,
            // but the TFM doesn't allow it
            await TestNoChangeforProject("Transitive.Dependency", "1.0.0", "1.1.0",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0", [(null, [("Transitive.Dependency", "[1.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0", [(null, [("Transitive.Dependency", "[1.1.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.1.0", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoChange_IfTargetFrameworkCouldNotBeEvaluated()
        {
            // Make sure we don't throw if the project's TFM is an unresolvable property
            await TestNoChangeforProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>$(PropertyThatCannotBeResolved)</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoChange_IfPeerDependenciesCannotBeEvaluated()
        {
            // make sure we don't throw if we find conflicting peer dependencies; this can happen in multi-tfm projects if the dependencies are too complicated to resolve
            // eventually this should be able to be resolved, but currently we can't branch on the different packages for different TFMs
            await TestNoChangeforProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    // initial packages
                    new MockNuGetPackage("Some.Package", "1.0.0",
                        DependencyGroups: [
                            ("net8.0", [("Transitive.Dependency", "8.0.0")]),
                            ("net9.0", [("Transitive.Dependency", "9.0.0")])
                        ]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "8.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "9.0.0", "net9.0"),

                    // what we're trying to update to, but will fail
                    new MockNuGetPackage("Some.Package", "1.1.0",
                        DependencyGroups: [
                            ("net8.0", [("Transitive.Dependency", "8.1.0")]),
                            ("net9.0", [("Transitive.Dependency", "9.1.0")])
                        ]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "8.1.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "9.1.0", "net9.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net9.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedResult: new() // success
                {
                    UpdateOperations = []
                }
            );
        }

        [Fact]
        public async Task ProcessingProjectWithWorkloadReferencesDoesNotFail()
        {
            // enumerating the build files will fail if the Aspire workload is not installed; this test ensures we can
            // still process the update
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;</TargetFrameworks>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;</TargetFrameworks>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task ProcessingProjectWithAspireDoesNotFailEvenThoughWorkloadIsNotInstalled()
        {
            // enumerating the build files will fail if the Aspire workload is not installed; this test ensures we can
            // still process the update
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task UnresolvablePropertyDoesNotStopOtherUpdates(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // the property `$(SomeUnresolvableProperty)` cannot be resolved
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }


        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task ProjectWithWorkloadsShouldNotFail(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // the property `$(SomeUnresolvableProperty)` cannot be resolved
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task UpdatingPackageAlsoUpdatesAnythingWithADependencyOnTheUpdatedPackage(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // updating Some.Package from 3.3.30 requires that Some.Package.Extensions also be updated
            await TestUpdateForProject("Some.Package", "3.3.30", "3.4.3",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.3.30", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.4.0", "net8.0"), // this will be ignored
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.4.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.3.30", "net8.0", [(null, [("Some.Package", "[3.3.30]")])]), // the dependency version is very strict with []
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.4.0", "net8.0", [(null, [("Some.Package", "[3.4.0]")])]), // this will be ignored
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.4.3", "net8.0", [(null, [("Some.Package", "[3.4.3]")])]),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.3.30" />
                        <PackageReference Include="Some.Package.Extensions" Version="3.3.30" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.4.3" />
                        <PackageReference Include="Some.Package.Extensions" Version="3.4.3" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageWithWhitespaceInTheXMLAttributeValue()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include=" Some.Package    " Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include=" Some.Package    " Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
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
                    _ => (401, "{}"), // everything is unauthorized
                };
            }
            using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
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
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedResult: new()
                {
                    Error = new PrivateSourceAuthenticationFailure([$"{http.BaseUrl.TrimEnd('/')}/index.json"]),
                    UpdateOperations = [],
                }
            );
        }

        [Fact]
        public async Task UpdateSdkManagedPackage_DirectDependency()
        {
            // To avoid a unit test that's tightly coupled to the installed SDK, several values are simulated,
            // including the runtime major version, the current Microsoft.NETCore.App.Ref package, and the package
            // correlation file.  Doing this requires a temporary file and environment variable override.
            var runtimeMajorVersion = Environment.Version.Major;
            var netCoreAppRefPackage = MockNuGetPackage.GetMicrosoftNETCoreAppRefPackage(runtimeMajorVersion);
            using var tempDirectory = new TemporaryDirectory();
            var packageCorrelationFile = Path.Combine(tempDirectory.DirectoryPath, "dotnet-package-correlation.json");
            await File.WriteAllTextAsync(packageCorrelationFile, $$"""
                {
                    "Runtimes": {
                        "{{runtimeMajorVersion}}.0.0": {
                            "Packages": {
                                "{{netCoreAppRefPackage.Id}}": "{{netCoreAppRefPackage.Version}}",
                                "System.Text.Json": "{{runtimeMajorVersion}}.0.98"
                            }
                        }
                    }
                }
                """);
            using var tempEnvironment = new TemporaryEnvironment([("DOTNET_PACKAGE_CORRELATION_FILE_PATH", packageCorrelationFile)]);

            // In the `packages` section below, we fake a `System.Text.Json` package with a low assembly version that
            // will always trigger the replacement so that can be detected and then the equivalent version is pulled
            // from the correlation file specified above.  In the original project contents, package version `x.0.98`
            // is reported which makes the update to `x.0.99` always possible.
            await TestUpdateForProject("System.Text.Json", $"{runtimeMajorVersion}.0.98", $"{runtimeMajorVersion}.0.99",
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true, InstallDotnetSdks = true },
                packages:
                [
                    // this assembly version is lower than what the SDK will have
                    MockNuGetPackage.CreatePackageWithAssembly("System.Text.Json", $"{runtimeMajorVersion}.0.0", $"net{runtimeMajorVersion}.0", assemblyVersion: $"{runtimeMajorVersion}.0.0.0"),
                    // this assembly version is greater than what the SDK will have
                    MockNuGetPackage.CreatePackageWithAssembly("System.Text.Json", $"{runtimeMajorVersion}.0.99", $"net{runtimeMajorVersion}.0", assemblyVersion: $"{runtimeMajorVersion}.99.99.99"),
                ],
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net{runtimeMajorVersion}.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="System.Text.Json" Version="{runtimeMajorVersion}.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles: [
                    ("global.json", $$"""
                        {
                            "sdk": {
                                "version": "{{runtimeMajorVersion}}.0.100",
                                "allowPrerelease": true,
                                "rollForward": "latestMinor"
                            }
                        }
                        """)
                ],
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net{runtimeMajorVersion}.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="System.Text.Json" Version="{runtimeMajorVersion}.0.99" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateSdkManagedPackage_TransitiveDependency()
        {
            // To avoid a unit test that's tightly coupled to the installed SDK, several values are simulated,
            // including the runtime major version, the current Microsoft.NETCore.App.Ref package, and the package
            // correlation file.  Doing this requires a temporary file and environment variable override.
            var runtimeMajorVersion = Environment.Version.Major;
            var netCoreAppRefPackage = MockNuGetPackage.GetMicrosoftNETCoreAppRefPackage(runtimeMajorVersion);
            using var tempDirectory = new TemporaryDirectory();
            var packageCorrelationFile = Path.Combine(tempDirectory.DirectoryPath, "dotnet-package-correlation.json");
            await File.WriteAllTextAsync(packageCorrelationFile, $$"""
                {
                    "Runtimes": {
                        "{{runtimeMajorVersion}}.0.0": {
                            "Packages": {
                                "{{netCoreAppRefPackage.Id}}": "{{netCoreAppRefPackage.Version}}",
                                "System.Text.Json": "{{runtimeMajorVersion}}.0.98"
                            }
                        }
                    }
                }
                """);
            using var tempEnvironment = new TemporaryEnvironment([("DOTNET_PACKAGE_CORRELATION_FILE_PATH", packageCorrelationFile)]);

            // In the `packages` section below, we fake a `System.Text.Json` package with a low assembly version that
            // will always trigger the replacement so that can be detected and then the equivalent version is pulled
            // from the correlation file specified above.  In the original project contents, package version `x.0.98`
            // is reported which makes the update to `x.0.99` always possible.
            await TestUpdateForProject("System.Text.Json", $"{runtimeMajorVersion}.0.98", $"{runtimeMajorVersion}.0.99",
                isTransitive: true,
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true, InstallDotnetSdks = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", $"net{runtimeMajorVersion}.0", [(null, [("System.Text.Json", $"[{runtimeMajorVersion}.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", $"net{runtimeMajorVersion}.0", [(null, [("System.Text.Json", $"[{runtimeMajorVersion}.0.99]")])]),
                    // this assembly version is lower than what the SDK will have
                    MockNuGetPackage.CreatePackageWithAssembly("System.Text.Json", $"{runtimeMajorVersion}.0.0", $"net{runtimeMajorVersion}.0", assemblyVersion: $"{runtimeMajorVersion}.0.0.0"),
                    // this assembly version is greater than what the SDK will have
                    MockNuGetPackage.CreatePackageWithAssembly("System.Text.Json", $"{runtimeMajorVersion}.0.99", $"net{runtimeMajorVersion}.0", assemblyVersion: $"{runtimeMajorVersion}.99.99.99"),
                ],
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net{runtimeMajorVersion}.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles: [
                    ("global.json", $$"""
                        {
                            "sdk": {
                                "version": "{{runtimeMajorVersion}}.0.100",
                                "allowPrerelease": true,
                                "rollForward": "latestMinor"
                            }
                        }
                        """)
                ],
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net{runtimeMajorVersion}.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task CentralPackageManagementStillWorksWithMultipleFeedsListedInConfig()
        {
            using var http1 = TestHttpServer.CreateTestNuGetFeed(
                MockNuGetPackage.CreateSimplePackage("Package1", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Package1", "1.0.1", "net9.0"));
            using var http2 = TestHttpServer.CreateTestNuGetFeed(MockNuGetPackage.CreateSimplePackage("Package2", "2.0.0", "net9.0"));
            await TestUpdate("Package1", "1.0.0", "1.0.1",
                useSolution: false,
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages: [],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                        <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
                        <MSBuildTreatWarningsAsErrors>true</MSBuildTreatWarningsAsErrors>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package1" />
                        <PackageReference Include="Package2" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles: [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Package1" Version="1.0.0" />
                            <PackageVersion Include="Package2" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("NuGet.Config", $"""
                        <configuration>
                          <packageSources>
                            <!-- explicitly _not_ calling "clear" because we also want the upstream sources in addition to these two remote sources -->
                            <add key="source_1" value="{http1.GetPackageFeedIndex()}" allowInsecureConnections="true" />
                            <add key="source_2" value="{http2.GetPackageFeedIndex()}" allowInsecureConnections="true" />
                          </packageSources>
                        </configuration>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                        <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
                        <MSBuildTreatWarningsAsErrors>true</MSBuildTreatWarningsAsErrors>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package1" />
                        <PackageReference Include="Package2" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected: [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Package1" Version="1.0.1" />
                            <PackageVersion Include="Package2" Version="2.0.0" />
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
