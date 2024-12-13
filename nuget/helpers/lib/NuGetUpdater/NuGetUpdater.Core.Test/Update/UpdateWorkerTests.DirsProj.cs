using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class DirsProj : UpdateWorkerTestBase
    {
        [Fact]
        public async Task UpdateSingleDependencyInDirsProj()
        {
            await TestUpdateForDirsProj("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/test-project.csproj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
                    ("src/test-project.csproj",
                        """
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
                expectedProjectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/test-project.csproj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("src/test-project.csproj",
                        """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task Update_MissingFileDoesNotThrow()
        {
            await TestUpdateForDirsProj("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.Build.Traversal">
                      <ItemGroup>
                        <ProjectReference Include="private\dirs.proj" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.Build.Traversal">
                      <ItemGroup>
                        <ProjectReference Include="private\dirs.proj" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles: []
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInNestedDirsProj()
        {
            await TestUpdateForDirsProj("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/dirs.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/dirs.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInNestedDirsProjUsingWildcard()
        {
            await TestUpdateForDirsProj("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/*.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="src/*.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInNestedDirsProjUsingRecursiveWildcard()
        {
            await TestUpdateForDirsProj("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="**/*.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.Build.NoTargets">

                      <ItemGroup>
                        <ProjectReference Include="**/*.proj" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
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
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        static async Task TestUpdateForDirsProj(
            string dependencyName,
            string oldVersion,
            string newVersion,
            string projectContents,
            string expectedProjectContents,
            bool isTransitive = false,
            (string Path, string Content)[]? additionalFiles = null,
            (string Path, string Content)[]? additionalFilesExpected = null,
            MockNuGetPackage[]? packages = null,
            ExperimentsManager? experimentsManager = null)
        {
            additionalFiles ??= [];
            additionalFilesExpected ??= [];

            var projectName = "dirs";
            var projectFileName = $"{projectName}.proj";
            var testFiles = additionalFiles.Prepend((projectFileName, projectContents)).ToArray();

            var actualResult = await RunUpdate(testFiles, async (temporaryDirectory) =>
            {
                await MockNuGetPackagesInDirectory(packages, temporaryDirectory);

                experimentsManager ??= new ExperimentsManager();
                var projectPath = Path.Combine(temporaryDirectory, projectFileName);
                var worker = new UpdaterWorker(experimentsManager, new TestLogger());
                await worker.RunAsync(temporaryDirectory, projectPath, dependencyName, oldVersion, newVersion, isTransitive);
            });

            var expectedResult = additionalFilesExpected.Prepend((projectFileName, expectedProjectContents)).ToArray();

            AssertContainsFiles(expectedResult, actualResult);
        }
    }
}
