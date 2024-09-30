using System.Text;
using System.Text.Json;
using System.Xml.Linq;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

using TestFile = (string Path, string Content);

public class RunWorkerTests
{
    [Fact]
    public async Task UpdateSinglePackageProducedExpectedAPIMessages()
    {
        var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-package" />""");
        await RunAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repoMetadata]),
            ],
            job: new Job()
            {
                PackageManager = "nuget",
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                    Directory = "some-dir",
                },
                AllowedUpdates =
                [
                    new() { UpdateType = "all" }
                ]
            },
            files:
            [
                ("some-dir/project.csproj", """
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
            expectedResult: new RunResult()
            {
                Base64DependencyFiles =
                [
                    new DependencyFile()
                    {
                        Directory = "/some-dir",
                        Name = "project.csproj",
                        Content = Convert.ToBase64String(Encoding.UTF8.GetBytes("""
                            <Project Sdk="Microsoft.NET.Sdk">
                              <PropertyGroup>
                                <TargetFramework>net8.0</TargetFramework>
                              </PropertyGroup>
                              <ItemGroup>
                                <PackageReference Include="Some.Package" Version="1.0.0" />
                              </ItemGroup>
                            </Project>
                            """))
                    }
                ],
                BaseCommitSha = "TEST-COMMIT-SHA",
            },
            expectedApiMessages:
            [
                new UpdatedDependencyList()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.0",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ]
                        }
                    ],
                    DependencyFiles = ["/some-dir/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions"
                    }
                },
                new CreatePullRequest()
                {
                    Dependencies =
                    [
                        new ReportedDependency()
                        {
                            Name = "Some.Package",
                            Version = "1.0.1",
                            Requirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.1",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                    Source = new()
                                    {
                                        SourceUrl = "https://nuget.example.com/some-package",
                                        Type = "nuget_repo",
                                    }
                                }
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements =
                            [
                                new ReportedRequirement()
                                {
                                    Requirement = "1.0.0",
                                    File = "/some-dir/project.csproj",
                                    Groups = ["dependencies"],
                                }
                            ],
                        }
                    ],
                    UpdatedDependencyFiles =
                    [
                        new DependencyFile()
                        {
                            Name = "project.csproj",
                            Directory = "some-dir",
                            Content = """
                                <Project Sdk="Microsoft.NET.Sdk">
                                  <PropertyGroup>
                                    <TargetFramework>net8.0</TargetFramework>
                                  </PropertyGroup>
                                  <ItemGroup>
                                    <PackageReference Include="Some.Package" Version="1.0.1" />
                                  </ItemGroup>
                                </Project>
                                """,
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = "TODO: message",
                    PrTitle = "TODO: title",
                    PrBody = "TODO: body",
                },
                new MarkAsProcessed()
                {
                    BaseCommitSha = "TEST-COMMIT-SHA",
                }
            ]
        );
    }

    private static async Task RunAsync(Job job, TestFile[] files, RunResult expectedResult, object[] expectedApiMessages, MockNuGetPackage[]? packages = null)
    {
        // arrange
        using var tempDirectory = new TemporaryDirectory();
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDirectory.DirectoryPath);
        foreach (var (path, content) in files)
        {
            var fullPath = Path.Combine(tempDirectory.DirectoryPath, path);
            var directory = Path.GetDirectoryName(fullPath)!;
            Directory.CreateDirectory(directory);
            await File.WriteAllTextAsync(fullPath, content);
        }

        // act
        var testApiHandler = new TestApiHandler();
        var worker = new RunWorker(testApiHandler, new Logger(verbose: false));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var actualResult = await worker.RunAsync(job, repoContentsPath, "TEST-COMMIT-SHA");
        var actualApiMessages = testApiHandler.ReceivedMessages.ToArray();

        // assert
        var actualRunResultJson = JsonSerializer.Serialize(actualResult);
        var expectedRunResultJson = JsonSerializer.Serialize(expectedResult);
        Assert.Equal(expectedRunResultJson, actualRunResultJson);
        for (int i = 0; i < Math.Min(actualApiMessages.Length, expectedApiMessages.Length); i++)
        {
            var actualMessage = actualApiMessages[i];
            var expectedMessage = expectedApiMessages[i];
            Assert.Equal(expectedMessage.GetType(), actualMessage.Type);

            var expectedContent = SerializeObjectAndType(expectedMessage);
            var actualContent = SerializeObjectAndType(actualMessage.Object);
            Assert.Equal(expectedContent, actualContent);
        }

        if (actualApiMessages.Length > expectedApiMessages.Length)
        {
            var extraApiMessages = actualApiMessages.Skip(expectedApiMessages.Length).Select(m => SerializeObjectAndType(m.Object)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but got {extraApiMessages.Length} extra:\n\t{string.Join("\n\t", extraApiMessages)}");
        }
        if (expectedApiMessages.Length > actualApiMessages.Length)
        {
            var missingApiMessages = expectedApiMessages.Skip(actualApiMessages.Length).Select(m => SerializeObjectAndType(m)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but only got {actualApiMessages.Length}; missing:\n\t{string.Join("\n\t", missingApiMessages)}");
        }
    }

    private static string SerializeObjectAndType(object obj)
    {
        return $"{obj.GetType().Name}:{JsonSerializer.Serialize(obj)}";
    }
}
