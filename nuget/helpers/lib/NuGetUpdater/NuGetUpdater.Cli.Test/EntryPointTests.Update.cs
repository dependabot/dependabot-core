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
        public async Task WithSolution()
        {
            await Run(path =>
                [
                    "update",
                    "--repo-root",
                    path,
                    "--solution-or-project",
                    Path.Combine(path, "path/to/solution.sln"),
                    "--dependency",
                    "Some.package",
                    "--new-version",
                    "13.0.1",
                    "--previous-version",
                    "7.0.1",
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
                ],
                initialFiles:
                [
                    ("path/to/solution.sln", """
                        Microsoft Visual Studio Solution File, Format Version 12.00
                        # Visual Studio 14
                        VisualStudioVersion = 14.0.22705.0
                        MinimumVisualStudioVersion = 10.0.40219.1
                        Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "my", "my.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
                        EndProject
                        Global
                            GlobalSection(SolutionConfigurationPlatforms) = preSolution
                            Debug|Any CPU = Debug|Any CPU
                            Release|Any CPU = Release|Any CPU
                            EndGlobalSection
                            GlobalSection(ProjectConfigurationPlatforms) = postSolution
                            {782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                            {782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.Build.0 = Debug|Any CPU
                            {782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.ActiveCfg = Release|Any CPU
                            {782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.Build.0 = Release|Any CPU
                            EndGlobalSection
                            GlobalSection(SolutionProperties) = preSolution
                            HideSolutionNode = FALSE
                            EndGlobalSection
                        EndGlobal
                        """),
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

        [Fact]
        public async Task WithProject()
        {
            await Run(path =>
                [
                    "update",
                    "--repo-root",
                    path,
                    "--solution-or-project",
                    Path.Combine(path, "path/to/my.csproj"),
                    "--dependency",
                    "Some.Package",
                    "--new-version",
                    "13.0.1",
                    "--previous-version",
                    "7.0.1",
                    "--verbose"
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

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario1()
        {
            await Run(path =>
                [
                    "update",
                    "--repo-root",
                    path,
                    "--solution-or-project",
                    Path.Combine(path, "path/to/my.csproj"),
                    "--dependency",
                    "CS-Script.Core",
                    "--new-version",
                    "2.0.0",
                    "--previous-version",
                    "1.3.1",
                    "--verbose"
                ],
                initialFiles:
                [
                    ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="CS-Script.Core" Version="1.3.1" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="3.4.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Scripting.Common" Version="3.4.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedFiles:
                [
                    ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="CS-Script.Core" Version="2.0.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="3.6.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Scripting.Common" Version="3.6.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario2()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "System.Text.Json",
                "--new-version",
                "4.7.2",
                "--previous-version",
                "4.6.0",
                "--verbose",
                "--transitive"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Azure.Core" Version="1.21.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Azure.Core" Version="1.22.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario3()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "Newtonsoft.Json",
                "--new-version",
                "13.0.1",
                "--previous-version",
                "12.0.1",
                "--verbose",
                "--transitive"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Newtonsoft.Json.Bson" Version="1.0.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                            <PackageReference Include="Newtonsoft.Json.Bson" Version="1.0.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario4()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "Microsoft.CodeAnalysis.Common",
                "--new-version",
                "4.10.0",
                "--previous-version",
                "4.9.2",
                "--verbose",
                "--transitive"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.9.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.10.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario5()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "Microsoft.CodeAnalysis.Common",
                "--new-version",
                "4.10.0",
                "--previous-version",
                "4.9.2",
                "--verbose"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.9.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.10.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario7()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "Buildalyzer",
                "--new-version",
                "7.0.1",
                "--previous-version",
                "6.0.4",
                "--verbose"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Buildalyzer" Version="6.0.4" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp.Scripting" Version="3.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="3.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="3.10.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Buildalyzer" Version="7.0.1" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp.Scripting" Version="4.0.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.0.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="4.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task ResolveDependencyConflicts_Scenario10()
        {
            await Run(path =>
            [
                "update",
                "--repo-root",
                path,
                "--solution-or-project",
                Path.Combine(path, "path/to/my.csproj"),
                "--dependency",
                "AutoMapper.Collection",
                "--new-version",
                "10.0.0",
                "--previous-version",
                "9.0.0",
                "--verbose"
            ],
        initialFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="AutoMapper.Extensions.Microsoft.DependencyInjection" Version="12.0.1" />
                            <PackageReference Include="AutoMapper" Version="12.0.1" />
                            <PackageReference Include="AutoMapper.Collection" Version="9.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
        expectedFiles:
            [
            ("path/to/my.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="AutoMapper.Extensions.Microsoft.DependencyInjection" Version="12.0.1" />
                            <PackageReference Include="AutoMapper" Version="12.0.1" />
                            <PackageReference Include="AutoMapper.Collection" Version="9.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
                );
        }

        [Fact]
        public async Task WithDirsProjAndDirectoryBuildPropsThatIsOutOfDirectoryButStillMatchingThePackage()
        {
            await Run(path =>
                [
                    "update",
                    "--repo-root",
                    path,
                    "--solution-or-project",
                    $"{path}/some-dir/dirs.proj",
                    "--dependency",
                    "Some.Package",
                    "--new-version",
                    "6.6.1",
                    "--previous-version",
                    "6.1.0",
                    "--verbose"
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "6.1.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "6.6.1", "net8.0"),
                ],
                initialFiles:
                [
                    ("some-dir/dirs.proj", """
                        <Project Sdk="Microsoft.Build.Traversal">
                          <ItemGroup>
                            <ProjectFile Include="project1/project.csproj" />
                            <ProjectReference Include="project2/project.csproj" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project1/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.1.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project2/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.1.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("other-dir/Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.1.0" />
                          </ItemGroup>

                        </Project>
                        """)
                ],
                expectedFiles:
                [
                    ("some-dir/dirs.proj", """
                        <Project Sdk="Microsoft.Build.Traversal">
                          <ItemGroup>
                            <ProjectFile Include="project1/project.csproj" />
                            <ProjectReference Include="project2/project.csproj" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project1/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.6.1" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project2/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.6.1" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("other-dir/Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="6.1.0" />
                          </ItemGroup>

                        </Project>
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
            var executableArgs = string.Join(" ",
            [
                executableName,
                "update",
                "--repo-root",
                tempDir.DirectoryPath,
                "--solution-or-project",
                projectPath,
                "--dependency",
                "Some.Package",
                "--new-version",
                "13.0.1",
                "--previous-version",
                "7.0.1",
                "--verbose"
            ]);

            // verify base run
            var workingDirectory = tempDir.DirectoryPath;
            if (workingDirectoryPath is not null)
            {
                workingDirectory = Path.Join(workingDirectory, workingDirectoryPath);
            }

            var (exitCode, output, error) = await ProcessEx.RunAsync("dotnet", executableArgs, workingDirectory: workingDirectory);
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
                    if (packages != null)
                    {
                        await MockNuGetPackagesInDirectory(packages, path);
                    }

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
