using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class Proj : DiscoveryWorkerTestBase
    {
        [Theory]
        [InlineData("ProjectFile")]
        [InlineData("ProjectReference")]
        public async Task DirsProjExpansion(string itemType)
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net8.0"),
                ],
                workspacePath: "dependabot",
                files:
                [
                    ("dependabot/projects.proj", $"""
                        <Project Sdk="Microsoft.Build.Traversal">
                          <ItemGroup>
                            <{itemType} Include="..\src\project1\project1.csproj" />
                            <{itemType} Include="..\other-dir\dirs.proj" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/project1/project1.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("other-dir/dirs.proj", $"""
                        <Project Sdk="Microsoft.Build.Traversal">
                          <ItemGroup>
                            <{itemType} Include="..\src\project2\project2.csproj" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/project2/project2.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.B" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "dependabot",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "../src/project1/project1.csproj",
                            Dependencies =
                            [
                                new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties =
                            [
                                new("TargetFramework", "net8.0", "src/project1/project1.csproj")
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "../src/project2/project2.csproj",
                            Dependencies =
                            [
                                new("Package.B", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties =
                            [
                                new("TargetFramework", "net8.0", "src/project2/project2.csproj")
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }
    }
}
