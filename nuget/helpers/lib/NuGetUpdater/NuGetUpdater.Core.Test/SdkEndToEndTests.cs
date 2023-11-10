using System.Threading.Tasks;
using Xunit;

namespace NuGetUpdater.Core.Test;

public class SdkEndToEndTests : EndToEndTestBase
{
    [Fact]
    public async Task UpdateSingleDependencyInSdkProject()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact(Skip = "package version via property NYI")]
    public async Task UpdateSingleDependencyWithVersionInPropertyInSameFile()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact(Skip = "package version via property NYI")]
    public async Task UpdateSingleDependencyWithVersionInDirectoryBuildPropsFile()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial project
            projectContents: """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            additionalFiles: new[]
            {
                // initial props file
                ("Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected project
            expectedProjectContents: """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            additionalFilesExpected: new[]
            {
                // expected props file
                ("Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact(Skip = "package version via property NYI")]
    public async Task UpdateSingleDependencyWithVersionInPropertyInPropsFile()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial project
            projectContents: """
            <Project Sdk="Microsoft.NET.Sdk">
              <Import Project="my-properties.props" />

              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            additionalFiles: new[]
            {
                // initial props file
                ("my-properties.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected project
            expectedProjectContents: """
            <Project Sdk="Microsoft.NET.Sdk">
              <Import Project="my-properties.props" />

              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>
            
              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            additionalFilesExpected: new[]
            {
                // expected props file
                ("my-properties.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }
}
