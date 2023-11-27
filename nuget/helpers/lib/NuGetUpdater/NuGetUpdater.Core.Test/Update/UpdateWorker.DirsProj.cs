using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class DirsProj : UpdateWorkerTestBase
    {
        public DirsProj()
        {
            MSBuildHelper.RegisterMSBuild();
        }

        [Fact]
        public async Task UpdateSingleDependencyInDirsProj()
        {
            await TestUpdateForDirsProj("Newtonsoft.Json", "9.0.1", "13.0.1",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.Build.NoTargets">

                  <ItemGroup>
                    <ProjectReference Include="src/test-project.csproj" />
                  </ItemGroup>

                </Project>
                """,
                additionalFiles: new (string Path, string Content)[]
                {
                    ("src/test-project.csproj",
                      """
                      <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                          <TargetFramework>netstandard2.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                          <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
                        </ItemGroup>
                      </Project>
                      """)
                },
                // expected
                expectedProjectContents: """
                <Project Sdk="Microsoft.Build.NoTargets">

                  <ItemGroup>
                    <ProjectReference Include="src/test-project.csproj" />
                  </ItemGroup>

                </Project>
                """,
                additionalFilesExpected: new (string Path, string Content)[]
                {
                    ("src/test-project.csproj",
                      """
                      <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                          <TargetFramework>netstandard2.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                          <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                        </ItemGroup>
                      </Project>
                      """)
                });
        }

        [Fact]
        public async Task UpdateSingleDependencyInNestedDirsProj()
        {
            await TestUpdateForDirsProj("Newtonsoft.Json", "9.0.1", "13.0.1",
                // initial
                projectContents: """
                <Project Sdk="Microsoft.Build.NoTargets">

                  <ItemGroup>
                    <ProjectReference Include="src/dirs.proj" />
                  </ItemGroup>

                </Project>
                """,
                additionalFiles: new (string Path, string Content)[]
                {
                    ("src/dirs.proj",
                      """
                      <Project Sdk="Microsoft.Build.NoTargets">

                        <ItemGroup>
                          <ProjectReference Include="test-project/test-project.csproj" />
                        </ItemGroup>

                      </Project>
                      """),
                    ("src/test-project/test-project.csproj",
                      """
                      <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                          <TargetFramework>netstandard2.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                          <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
                        </ItemGroup>
                      </Project>
                      """)
                },
                // expected
                expectedProjectContents: """
                <Project Sdk="Microsoft.Build.NoTargets">

                  <ItemGroup>
                    <ProjectReference Include="src/dirs.proj" />
                  </ItemGroup>

                </Project>
                """,
                additionalFilesExpected: new (string Path, string Content)[]
                {
                    ("src/dirs.proj",
                      """
                      <Project Sdk="Microsoft.Build.NoTargets">

                        <ItemGroup>
                          <ProjectReference Include="test-project/test-project.csproj" />
                        </ItemGroup>

                      </Project>
                      """),
                    ("src/test-project/test-project.csproj",
                      """
                      <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                          <TargetFramework>netstandard2.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                          <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                        </ItemGroup>
                      </Project>
                      """)
                });
        }

        static async Task TestUpdateForDirsProj(
            string dependencyName,
            string oldVersion,
            string newVersion,
            string projectContents,
            string expectedProjectContents,
            bool isTransitive = false,
            (string Path, string Content)[]? additionalFiles = null,
            (string Path, string Content)[]? additionalFilesExpected = null)
        {
            additionalFiles ??= Array.Empty<(string Path, string Content)>();
            additionalFilesExpected ??= Array.Empty<(string Path, string Content)>();

            var projectName = "dirs";
            var projectFileName = $"{projectName}.proj";
            var testFiles = additionalFiles.Prepend((projectFileName, projectContents)).ToArray();

            var actualResult = await RunUpdate(testFiles, async (temporaryDirectory) =>
            {
                var projectPath = Path.Combine(temporaryDirectory, projectFileName);
                var worker = new UpdaterWorker(new Logger(verbose: true));
                await worker.RunAsync(temporaryDirectory, projectPath, dependencyName, oldVersion, newVersion, isTransitive);
            });

            var expectedResult = additionalFilesExpected.Prepend((projectFileName, expectedProjectContents)).ToArray();

            AssertContainsFiles(expectedResult, actualResult);
        }
    }
}
