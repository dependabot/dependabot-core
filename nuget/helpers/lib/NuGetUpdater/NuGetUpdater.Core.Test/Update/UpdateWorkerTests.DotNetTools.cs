using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class DotNetTools : UpdateWorkerTestBase
    {
        [Fact]
        public async Task NoChangeWhenDotNetToolsJsonNotFound()
        {
            await TestNoChangeforProject("Microsoft.BotSay", "1.0.0", "1.1.0",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
                  </ItemGroup>
                </Project>
                """);
        }

        [Fact]
        public async Task NoChangeWhenDependencyNotFound()
        {
            await TestNoChangeforProject("Microsoft.BotSay", "1.0.0", "1.1.0",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          }
                        }
                        """)
                ]);
        }

        [Fact]
        public async Task NoChangeWhenDotNetToolsJsonInUnexpectedLocation()
        {
            await TestNoChangeforProject("Microsoft.BotSay", "1.0.0", "1.1.0",
                // initial
                projectFilePath: "src/project/project.csproj",
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          }
                        }
                        """)
                ]);
        }

        [Fact]
        public async Task UpdateSingleDependencyInDirsProj()
        {
            await TestUpdateForProject("Microsoft.BotSay", "1.0.0", "1.1.0",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "microsoft.botsay": {
                              "version": "1.0.0",
                              "commands": [
                                "botsay"
                              ]
                            },
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
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
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "microsoft.botsay": {
                              "version": "1.1.0",
                              "commands": [
                                "botsay"
                              ]
                            },
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          }
                        }
                        """)
                ]);
        }

        [Fact]
        public async Task UpdateSingleDependencyWithComments()
        {
            await TestUpdateForProject("Microsoft.BotSay", "1.0.0", "1.1.0",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "microsoft.botsay": {
                              // this is a deep comment
                              "version": "1.0.0",
                              "commands": [
                                "botsay"
                              ]
                            },
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
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
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                            "microsoft.botsay": {
                              // this is a deep comment
                              "version": "1.1.0",
                              "commands": [
                                "botsay"
                              ]
                            },
                            "dotnetsay": {
                              "version": "2.1.3",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          }
                        }
                        """)
                ]);
        }
    }
}
