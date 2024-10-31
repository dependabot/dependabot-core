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
                    AllowedUpdates = [
                        new()
                        {
                            UpdateType = "all"
                        }
                    ],
                    Source = new()
                    {
                        Provider = "github",
                        Repo = "test",
                        Directory = "src",
                    }
                },
                expectedUrls:
                [
                    "/update_jobs/TEST-ID/update_dependency_list",
                    "/update_jobs/TEST-ID/increment_metric",
                    "/update_jobs/TEST-ID/create_pull_request",
                    "/update_jobs/TEST-ID/mark_as_processed",
                ]
            );
        }

        private static async Task RunAsync(TestFile[] files, Job job, string[] expectedUrls, MockNuGetPackage[]? packages = null)
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
            using var http = TestHttpServer.CreateTestStringServer(url =>
            {
                actualUrls.Add(new Uri(url).PathAndQuery);
                return (200, "ok");
            });
            var args = new List<string>()
            {
                "run",
                "--job-path",
                jobPath,
                "--repo-contents-path",
                tempDirectory.DirectoryPath,
                "--api-url",
                http.BaseUrl,
                "--job-id",
                "TEST-ID",
                "--output-path",
                Path.Combine(tempDirectory.DirectoryPath, "output.json"),
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

            Assert.True(result == 0, output.ToString());
            Assert.Equal(expectedUrls, actualUrls);
        }
    }
}
