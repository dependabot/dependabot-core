using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test;

public class DirsProjEndToEndTests : EndToEndTestBase
{
    [Fact]
    public async Task UpdateSingleDependencyInDirsProj()
    {
        var additionalFiles = new (string Path, string Content)[]
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
        };

        var additionalFilesExpected = new (string Path, string Content)[]
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
        };

        await TestUpdateForDirsProj("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.Build.NoTargets">

              <ItemGroup>
                <ProjectReference Include="src/test-project.csproj" />
              </ItemGroup>

            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.Build.NoTargets">

              <ItemGroup>
                <ProjectReference Include="src/test-project.csproj" />
              </ItemGroup>

            </Project>
            """, additionalFiles, additionalFilesExpected);
    }

    [Fact]
    public async Task UpdateSingleDependencyInNestedDirsProj()
    {
        var additionalFiles = new (string Path, string Content)[]
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
        };

        var additionalFilesExpected = new (string Path, string Content)[]
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
        };

        await TestUpdateForDirsProj("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.Build.NoTargets">

              <ItemGroup>
                <ProjectReference Include="src/dirs.proj" />
              </ItemGroup>

            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.Build.NoTargets">

              <ItemGroup>
                <ProjectReference Include="src/dirs.proj" />
              </ItemGroup>

            </Project>
            """, additionalFiles, additionalFilesExpected);

    }

    static async Task TestUpdateForDirsProj(
        string dependencyName,
        string oldVersion,
        string newVersion,
        string projectContents,
        string expectedProjectContents,
        (string Path, string Content)[]? additionalFiles = null,
        (string Path, string Content)[]? additionalFilesExpected = null)
    {
        var projectName = "dirs";
        var projectFileName = $"{projectName}.proj";
        var testFiles = new List<(string Path, string Content)>()
        {
            (projectFileName, projectContents),
        };
        if (additionalFiles is not null)
        {
            testFiles.AddRange(additionalFiles);
        }

        var actualResult = await RunUpdate(testFiles.ToArray(), async (temporaryDirectory) =>
        {
            var projectPath = Path.Combine(temporaryDirectory, projectFileName);
            var worker = new NuGetUpdaterWorker(verbose: true);
            await worker.RunAsync(temporaryDirectory, projectPath, dependencyName, oldVersion, newVersion);
        });

        var expectedResult = new List<(string Path, string Content)>()
        {
            (projectFileName, expectedProjectContents)
        };

        if (additionalFilesExpected is not null)
        {
            expectedResult.AddRange(additionalFilesExpected);
        }

        AssertContainsFiles(expectedResult.ToArray(), actualResult);
    }
}
