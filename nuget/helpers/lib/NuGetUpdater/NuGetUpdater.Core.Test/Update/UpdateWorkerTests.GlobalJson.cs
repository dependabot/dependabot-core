using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class GlobalJson : UpdateWorkerTestBase
    {
        [Fact]
        public async Task NoChangeWhenGlobalJsonNotFound()
        {
            await TestNoChangeforProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
                packages: [],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoChangeWhenDependencyNotFound()
        {
            await TestNoChangeforProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
                packages: [],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task NoChangeWhenGlobalJsonInUnexpectedLocation()
        {
            await TestNoChangeforProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
                packages: [],
                // initial
                projectFilePath: "src/project/project.csproj",
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("eng/global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Microsoft.Build.Traversal": "3.2.0"
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependency()
        {
            await TestUpdateForProject("Some.MSBuild.Sdk", "3.2.0", "4.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "3.2.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "4.1.0"),
                ],
                // initial
                projectFilePath: "src/project/project.csproj",
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("src/global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Some.MSBuild.Sdk": "3.2.0"
                          }
                        }
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("src/global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Some.MSBuild.Sdk": "4.1.0"
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateDependencyWithComments()
        {
            await TestUpdateForProject("Some.MSBuild.Sdk", "3.2.0", "4.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "3.2.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "4.1.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("global.json", """
                        {
                          // this is a comment
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            // this is a deep comment
                            "Some.MSBuild.Sdk": "3.2.0"
                          }
                        }
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("global.json", """
                        {
                          // this is a comment
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            // this is a deep comment
                            "Some.MSBuild.Sdk": "4.1.0"
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateDependencyWithTrailingComma()
        {
            await TestUpdateForProject("Some.MSBuild.Sdk", "3.2.0", "4.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "3.2.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "4.1.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Some.MSBuild.Sdk": "3.2.0"
                          },
                        }
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.3" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected file no longer has the trailing comma because the parser removes it.
                additionalFilesExpected:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Some.MSBuild.Sdk": "4.1.0"
                          }
                        }
                        """)
                ]
            );
        }
    }
}
