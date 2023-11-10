using System.Collections.Generic;
using System.Threading.Tasks;
using Xunit;

namespace NuGetUpdater.Core.Test
{
  public class PackagesConfigEndToEndTests : EndToEndTestBase
    {
        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfig()
        {
            // update Newtonsoft.Json from 7.0.1 to 13.0.1
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "13.0.1",
                // existing
                """
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
                """,
                """
                <packages>
                  <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
                // expected
                """
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
                """,
                """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                </packages>
                """);
        }

        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfigButNotToLatest()
        {
            // update Newtonsoft.Json from 7.0.1 to 9.0.1, purposefully not updating all the way to the newest
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "9.0.1",
                // existing
                """
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
                """,
                """
                <packages>
                  <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
                // expected
                """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Newtonsoft.Json, Version=9.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Newtonsoft.Json.9.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Newtonsoft.Json" version="9.0.1" targetFramework="net45" />
                </packages>
                """);
        }

        [Fact]
        public async Task UpdateSpecifiedVersionInPackagesConfigButNotOthers()
        {
            // update Newtonsoft.Json from 7.0.1 to 13.0.1, but leave HtmlAgilityPack alone
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "13.0.1",
                // existing
                """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="HtmlAgilityPack, Version=1.11.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\HtmlAgilityPack.1.11.0\lib\net45\HtmlAgilityPack.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                """
                <packages>
                  <package id="HtmlAgilityPack" version="1.11.0" targetFramework="net45" />
                  <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
                // expected
                """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="HtmlAgilityPack, Version=1.11.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\HtmlAgilityPack.1.11.0\lib\net45\HtmlAgilityPack.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="HtmlAgilityPack" version="1.11.0" targetFramework="net45" />
                  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                </packages>
                """);
        }

        [Fact]
        public async Task UpdatePackagesConfigWithNonStandardLocationOfPackagesDirectory()
        {
            // update Newtonsoft.Json from 7.0.1 to 13.0.1 with the actual assembly in a non-standard location
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "13.0.1",
                // existing
                """
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
                      <HintPath>some-non-standard-location\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                """
                <packages>
                  <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
                // expected
                """
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
                      <HintPath>some-non-standard-location\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                </packages>
                """);
        }

        protected static async Task TestUpdateForProject(
            string dependencyName,
            string oldVersion,
            string newVersion,
            string projectContents,
            string packagesConfigContents,
            string expectedProjectContents,
            string expectedPackagesConfigContents,
            (string Path, string Content)[]? additionalFiles = null,
            (string Path, string Content)[]? additionalFilesExpected = null)
        {
            var realizedAdditionalFiles = new List<(string Path, string Content)>()
            {
                ("packages.config", packagesConfigContents),
            };
            if (additionalFiles is not null)
            {
                realizedAdditionalFiles.AddRange(additionalFiles);
            }

            var realizedAdditionalFilesExpected = new List<(string Path, string Content)>()
            {
                ("packages.config", expectedPackagesConfigContents),
            };
            if (additionalFilesExpected is not null)
            {
                realizedAdditionalFilesExpected.AddRange(additionalFilesExpected);
            }

            await TestUpdateForProject(dependencyName, oldVersion, newVersion, projectContents, expectedProjectContents, realizedAdditionalFiles.ToArray(), realizedAdditionalFilesExpected.ToArray());
        }
    }
}
