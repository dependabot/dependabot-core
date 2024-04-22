using System.Threading.Tasks;

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
            await TestNoChangeforProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
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
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          }
                        }
                        """)
                ]);
        }

        [Fact]
        public async Task NoChangeWhenGlobalJsonInUnexpectedLocation()
        {
            await TestNoChangeforProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
                // initial
                projectFilePath: "src/project/project.csproj",
                projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                
                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
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
                ]);
        }

        [Fact]
        public async Task UpdateSingleDependency()
        {
            await TestUpdateForProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
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
                    ("src/global.json", """
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
                    ("src/global.json", """
                        {
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Microsoft.Build.Traversal": "4.1.0"
                          }
                        }
                        """)
                ]);
        }

        [Fact]
        public async Task UpdateDependencyWithComments()
        {
            await TestUpdateForProject("Microsoft.Build.Traversal", "3.2.0", "4.1.0",
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
                    ("global.json", """
                        {
                          // this is a comment
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            // this is a deep comment
                            "Microsoft.Build.Traversal": "3.2.0"
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
                    ("global.json", """
                        {
                          // this is a comment
                          "sdk": {
                            "version": "6.0.405",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            // this is a deep comment
                            "Microsoft.Build.Traversal": "4.1.0"
                          }
                        }
                        """)
                ]);
        }
    }
}
