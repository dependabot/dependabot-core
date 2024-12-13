using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class DotNetTools : UpdateWorkerTestBase
    {
        [Fact]
        public async Task NoChangeWhenDotNetToolsJsonNotFound()
        {
            await TestNoChangeforProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
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
                    """
            );
        }

        [Fact]
        public async Task NoChangeWhenDependencyNotFound()
        {
            await TestNoChangeforProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some-Other-Tool", "2.0.0", "net8.0"),
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
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some-other-tool": {
                              "version": "2.0.0",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task NoChangeWhenDotNetToolsJsonInUnexpectedLocation()
        {
            await TestNoChangeforProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some-Other-Tool", "2.0.0", "net8.0"),
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
                    ("eng/.config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some-other-tool": {
                              "version": "2.0.0",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependency()
        {
            await TestUpdateForProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
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
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              "version": "1.0.0",
                              "commands": [
                                "some.dotnet.tool"
                              ]
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
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
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              "version": "1.1.0",
                              "commands": [
                                "some.dotnet.tool"
                              ]
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyWithComments()
        {
            await TestUpdateForProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
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
                    (".config/dotnet-tools.json", """
                        {
                          // this is a comment
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              // this is a deep comment
                              "version": "1.0.0",
                              "commands": [
                                "some.dotnet.tool"
                              ]
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
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
                    (".config/dotnet-tools.json", """
                        {
                          // this is a comment
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              // this is a deep comment
                              "version": "1.1.0",
                              "commands": [
                                "some.dotnet.tool"
                              ]
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
                          }
                        }
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyWithTrailingComma()
        {
            await TestUpdateForProject("Some.DotNet.Tool", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.3", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net8.0"),
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
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              "version": "1.0.0",
                              "commands": [
                                "some.dotnet.tool"
                              ],
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ],
                            }
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
                // expected files no longer have trailing commas in the json
                additionalFilesExpected:
                [
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some.dotnet.tool": {
                              "version": "1.1.0",
                              "commands": [
                                "some.dotnet.tool"
                              ]
                            },
                            "some-other-tool": {
                              "version": "2.1.3",
                              "commands": [
                                "some-other-tool"
                              ]
                            }
                          }
                        }
                        """)
                ]
            );
        }
    }
}
