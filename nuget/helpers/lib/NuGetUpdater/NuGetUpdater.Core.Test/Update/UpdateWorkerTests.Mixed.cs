using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class Mixed : UpdateWorkerTestBase
    {
        [Fact]
        public async Task ForPackagesProject_UpdatePackageReference_InBuildProps()
        {
            // update Newtonsoft.Json from 7.0.1 to 13.0.1
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "13.0.1",
                // existing
                projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
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
                additionalFiles:
                [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Newtonsoft.Json" Version="7.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
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
                additionalFilesExpected:
                [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]);
        }
    }
}
