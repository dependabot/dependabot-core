using System.Text;
using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

public partial class EntryPointTests
{
    public class Run
    {
        [Fact]
        public async Task Run_Simple()
        {
            // verify we can pass command line arguments and hit the appropriate URLs
            await RunAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0"),
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
                    "POST /update_jobs/TEST-ID/increment_metric",
                    "POST /update_jobs/TEST-ID/update_dependency_list",
                    "POST /update_jobs/TEST-ID/create_pull_request",
                    "PATCH /update_jobs/TEST-ID/mark_as_processed",
                ]
            );
        }

        [Fact]
        public async Task Run_ExitCodeIsSet()
        {
            using var http = TestHttpServer.CreateTestStringServer(url =>
            {
                var uri = new Uri(url, UriKind.Absolute);
                var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
                return uri.PathAndQuery switch
                {
                    // initial and search query are good, update should be possible...
                    "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                    _ => (401, "") // everything else is unauthorized
                };
            });
            var feedUrl = $"{http.BaseUrl.TrimEnd('/')}/index.json";
            await RunAsync(
                files: [
                    ("NuGet.Config", $"""
                        <configuration>
                          <packageSources>
                            <clear />
                            <add key="private_feed" value="{feedUrl}" allowInsecureConnections="true" />
                          </packageSources>
                        </configuration>
                        """),
                    ("src/Directory.Build.props", "<Project />"),
                    ("src/Directory.Build.targets", "<Project />"),
                    ("src/Directory.Packages.props", "<Project />"),
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3" />
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
                    "POST /update_jobs/TEST-ID/increment_metric",
                    "POST /update_jobs/TEST-ID/record_update_job_error",
                    "PATCH /update_jobs/TEST-ID/mark_as_processed",
                ],
                expectedExitCode: 1
            );
        }

        private static async Task RunAsync(TestFile[] files, Job job, string[] expectedUrls, MockNuGetPackage[]? packages = null, string? repoContentsPath = null, int expectedExitCode = 0)
        {
            using var tempDirectory = new TemporaryDirectory();

            // write test files
            foreach (var testFile in files)
            {
                var fullPath = Path.Join(tempDirectory.DirectoryPath, testFile.Path);
                var directory = Path.GetDirectoryName(fullPath)!;
                Directory.CreateDirectory(directory);
                await File.WriteAllTextAsync(fullPath, testFile.Content);
            }

            // write job file
            var jobPath = Path.Combine(tempDirectory.DirectoryPath, "job.json");
            await File.WriteAllTextAsync(jobPath, JsonSerializer.Serialize(new { Job = job }, RunWorker.SerializerOptions));

            // save packages
            await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDirectory.DirectoryPath);

            var actualUrls = new List<string>();
            using var http = TestHttpServer.CreateTestStringServer((method, url) =>
            {
                actualUrls.Add($"{method} {new Uri(url).PathAndQuery}");
                return (200, "ok");
            });
            var args = new List<string>()
            {
                "run",
                "--job-path",
                jobPath,
                "--repo-contents-path",
                repoContentsPath ?? tempDirectory.DirectoryPath,
                "--api-url",
                http.BaseUrl,
                "--job-id",
                "TEST-ID",
                "--base-commit-sha",
                "BASE-COMMIT-SHA"
            };

            var output = new StringBuilder();
            // redirect stdout
            var originalOut = Console.Out;
            Console.SetOut(new StringWriter(output));
            int result = -1;
            try
            {
                result = await Program.Main(args.ToArray());
            }
            catch
            {
                // restore stdout
                Console.SetOut(originalOut);
                throw;
            }

            Assert.True(result == expectedExitCode, $"Expected exit code {expectedExitCode} but got {result}.\nSTDOUT:\n" + output.ToString());
            Assert.Equal(expectedUrls, actualUrls);
        }
    }
}
