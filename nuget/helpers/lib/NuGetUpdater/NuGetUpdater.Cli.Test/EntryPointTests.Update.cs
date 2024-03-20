using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

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
                    "Newtonsoft.Json",
                    "--new-version",
                    "13.0.1",
                    "--previous-version",
                    "7.0.1",
                ],
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
                            <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                              <HintPath>packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ],
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
                            <Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                              <HintPath>packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ]);
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
                    "Newtonsoft.Json",
                    "--new-version",
                    "13.0.1",
                    "--previous-version",
                    "7.0.1",
                    "--verbose"
                ],
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
                            <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                              <HintPath>packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ],
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
                            <Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                              <HintPath>packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """)
                ]);
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
                    "NuGet.Versioning",
                    "--new-version",
                    "6.6.1",
                    "--previous-version",
                    "6.1.0",
                    "--verbose"
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
                            <TargetFramework>net6.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.1.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project2/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net6.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.1.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("other-dir/Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                        
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.1.0" />
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
                    ("some-dir/project1/project.csproj",
                        """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net6.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.6.1" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("some-dir/project2/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net6.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.6.1" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("other-dir/Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                        
                          <ItemGroup>
                            <PackageReference Include="NuGet.Versioning" Version="6.1.0" />
                          </ItemGroup>

                        </Project>
                        """)
                ]
            );
        }

        private static async Task Run(Func<string, string[]> getArgs, (string Path, string Content)[] initialFiles, (string, string)[] expectedFiles)
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
