using System.IO;
using System.Text;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Test;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Cli.Test;

public partial class EntryPointTests
{
    public class Update : UpdateWorkerTestBase
    {
        [Fact]
        public async Task WithProject()
        {
            await Run(path =>
                [
                    "update",
                    "--job-id",
                    "TEST-JOB-ID",
                    "--job-path",
                    Path.Combine(path, "job.json"),
                    "--repo-root",
                    path,
                    "--solution-or-project",
                    Path.Combine(path, "path/to/my.csproj"),
                    "--dependency",
                    "Some.Package",
                    "--new-version",
                    "13.0.1",
                    "--previous-version",
                    "7.0.1"
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
                ],
                initialFiles:
                [
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="Some.Package">
                              <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ],
                expectedFiles:
                [
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="Some.Package">
                              <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ]
            );
        }

        [Theory]
        [InlineData(null)]
        [InlineData("src")]
        public async Task UpdaterDoesNotUseRepoGlobalJsonForMSBuildTasks(string? workingDirectoryPath)
        {
            // This is a _very_ specific scenario where the `NuGetUpdater.Cli` tool might pick up a `global.json` from
            // the root of the repo under test and use it's `sdk` property when trying to locate MSBuild.  To properly
            // test this, it must be tested in a new process where MSBuild has not been loaded yet and the runner tool
            // must be started with its working directory at the test repo's root.
            using var tempDir = new TemporaryDirectory();

            MockNuGetPackage[] testPackages =
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
            ];
            await MockNuGetPackagesInDirectory(testPackages, tempDir.DirectoryPath);
            await MockJobFileInDirectory(tempDir.DirectoryPath);

            var globalJsonPath = Path.Join(tempDir.DirectoryPath, "global.json");
            var srcGlobalJsonPath = Path.Join(tempDir.DirectoryPath, "src", "global.json");
            string globalJsonContent = """
                {
                  "sdk": {
                    "version": "99.99.99"
                  }
                }
                """;
            await File.WriteAllTextAsync(globalJsonPath, globalJsonContent);
            Directory.CreateDirectory(Path.Join(tempDir.DirectoryPath, "src"));
            await File.WriteAllTextAsync(srcGlobalJsonPath, globalJsonContent);
            var projectPath = Path.Join(tempDir.DirectoryPath, "src", "project.csproj");
            await File.WriteAllTextAsync(projectPath, """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Package" Version="7.0.1" />
                  </ItemGroup>
                </Project>
                """);
            var executableName = Path.Join(Path.GetDirectoryName(GetType().Assembly.Location), "NuGetUpdater.Cli.dll");
            IEnumerable<string> executableArgs = [
                executableName,
                "update",
                "--job-id",
                "TEST-JOB-ID",
                "--job-path",
                Path.Combine(tempDir.DirectoryPath, "job.json"),
                "--repo-root",
                tempDir.DirectoryPath,
                "--solution-or-project",
                projectPath,
                "--dependency",
                "Some.Package",
                "--new-version",
                "13.0.1",
                "--previous-version",
                "7.0.1"
            ];

            // verify base run
            var workingDirectory = tempDir.DirectoryPath;
            if (workingDirectoryPath is not null)
            {
                workingDirectory = Path.Join(workingDirectory, workingDirectoryPath);
            }

            var (exitCode, output, error) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(executableArgs, workingDirectory, new ExperimentsManager() { InstallDotnetSdks = false });
            Assert.True(exitCode == 0, $"Error running update on unsupported SDK.\nSTDOUT:\n{output}\nSTDERR:\n{error}");

            // verify project update
            var updatedProjectContents = await File.ReadAllTextAsync(projectPath);
            Assert.Contains("13.0.1", updatedProjectContents);

            // verify `global.json` untouched
            var updatedGlobalJsonContents = await File.ReadAllTextAsync(globalJsonPath);
            Assert.Contains("99.99.99", updatedGlobalJsonContents);

            // verify `src/global.json` untouched
            var updatedSrcGlobalJsonContents = await File.ReadAllTextAsync(srcGlobalJsonPath);
            Assert.Contains("99.99.99", updatedGlobalJsonContents);
        }

        private static async Task Run(Func<string, string[]> getArgs, (string Path, string Content)[] initialFiles, (string, string)[] expectedFiles, MockNuGetPackage[]? packages = null)
        {
            var actualFiles = await RunUpdate(initialFiles, async path =>
            {
                var sb = new StringBuilder();
                var writer = new StringWriter(sb);

                var originalOut = Console.Out;
                var originalErr = Console.Error;
                Console.SetOut(writer);
                Console.SetError(writer);

                try
                {
                    await MockJobFileInDirectory(path);
                    await MockNuGetPackagesInDirectory(packages, path);

                    var args = getArgs(path);
                    var result = await Program.Main(args);
                    if (result != 0)
                    {
                        throw new Exception($"Program exited with code {result}.\nOutput:\n\n{sb}");
                    }
                }
                finally
                {
                    Console.SetOut(originalOut);
                    Console.SetError(originalErr);
                }
            });

            AssertContainsFiles(expectedFiles, actualFiles);
        }
    }
}
