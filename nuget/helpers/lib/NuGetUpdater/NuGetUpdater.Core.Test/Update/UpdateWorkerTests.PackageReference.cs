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
    }
}
