using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

public partial class EntryPointTests
{
    public class Graph
    {
        [Fact]
        public async Task Graph_Simple()
        {
            // verify we can pass command line arguments for graph command
            await RunAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                ],
                files:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Build.targets", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                job: new Job()
                {
                    Source = new()
                    {
                        Provider = "github",
                        Repo = "test",
                        Directory = "src",
                    }
                },
                expectedUrls:
                [
                    "POST /update_jobs/TEST-ID/create_dependency_submission",
                    "PATCH /update_jobs/TEST-ID/mark_as_processed",
                ]
            );
        }

        private static Task RunAsync(TestFile[] files, Job job, string[] expectedUrls, MockNuGetPackage[]? packages = null, string? repoContentsPath = null, int expectedExitCode = 0)
            => EntryPointTestHelper.RunAsync("graph", files, job, expectedUrls, packages, repoContentsPath, expectedExitCode);
    }
}
