using NuGet.Versioning;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class PullRequestMessageTests
{
    [Theory]
    [MemberData(nameof(GetPullRequestApiMessageData))]
    public void GetPullRequestApiMessage(Job job, DependencyFile[] updatedFiles, ReportedDependency[] updatedDependencies, UpdateOperationBase[] updateOperationsPerformed, MessageBase expectedMessage)
    {
        var actualMessage = RunWorker.GetPullRequestApiMessage(job, updatedFiles, updatedDependencies, [.. updateOperationsPerformed], "TEST-COMMIT-SHA");
        Assert.NotNull(actualMessage);
        actualMessage = actualMessage switch
        {
            // this isn't the place to verify the generated text
            CreatePullRequest create => create with { CommitMessage = RunWorkerTests.TestPullRequestCommitMessage, PrTitle = RunWorkerTests.TestPullRequestTitle, PrBody = RunWorkerTests.TestPullRequestBody },
            UpdatePullRequest update => update with { CommitMessage = RunWorkerTests.TestPullRequestCommitMessage, PrTitle = RunWorkerTests.TestPullRequestTitle, PrBody = RunWorkerTests.TestPullRequestBody },
            _ => actualMessage,
        };
        Assert.Equal(expectedMessage.GetType(), actualMessage.GetType());
        var actualMessageJson = HttpApiHandler.Serialize(actualMessage);
        var expectedMessageJson = HttpApiHandler.Serialize(expectedMessage);
        Assert.Equal(expectedMessageJson, actualMessageJson);
    }

    public static IEnumerable<object[]> GetPullRequestApiMessageData()
    {
        // candidate pull request does not match existing, no matching security advisory => create
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                }
            },
            // updatedFiles
            new[]
            {
                new DependencyFile()
                {
                    Directory = "/src/",
                    Name = "project.csproj",
                    Content = "project contents irrelevant",
                }
            },
            // updatedDependencies
            new[]
            {
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    Version = "1.0.1",
                    Requirements = [],
                }
            },
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Dependency",
                    NewVersion = NuGetVersion.Parse("1.0.1"),
                    UpdatedFiles = ["/src/project.csproj"]
                }
            },
            // expectedMessage
            new CreatePullRequest()
            {
                Dependencies = [new ReportedDependency() { Name = "Some.Dependency", Version = "1.0.1", Requirements = [] }],
                UpdatedDependencyFiles = [new DependencyFile() { Directory = "/src/", Name = "project.csproj", Content = "project contents irrelevant" } ],
                BaseCommitSha = "TEST-COMMIT-SHA",
                CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                PrTitle = RunWorkerTests.TestPullRequestTitle,
                PrBody = RunWorkerTests.TestPullRequestBody,
                DependencyGroup = null,
            }
        ];

        // candidate pull request matches existing, no matching security advisory found => close
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                SecurityUpdatesOnly = true,
                SecurityAdvisories = [], // no matching advisory
                ExistingPullRequests = [
                    new PullRequest()
                    {
                        Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("1.0.1") }]
                    }
                ]
            },
            // updatedFiles
            Array.Empty<DependencyFile>(), // not used
            // updatedDependencies
            new[]
            {
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    Version = "1.0.1",
                    Requirements = [], // not used
                }
            },
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Dependency",
                    NewVersion = NuGetVersion.Parse("1.0.1"),
                    UpdatedFiles = ["/src/project.csproj"]
                }
            },
            // expectedMessage
            new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "up_to_date" },
        ];

        // broken
        // started a security job, but no changes were made => find matching existing PR and close
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [
                    new PullRequest()
                    {
                        Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("1.0.1") }]
                    }
                ],
                SecurityAdvisories = [
                    new Advisory()
                    {
                        DependencyName = "Some.Dependency",
                    }
                ]
            },
            // updatedFiles
            Array.Empty<DependencyFile>(),
            // updatedDependencies
            Array.Empty<ReportedDependency>(),
            // updateOperationsPerformed
            new UpdateOperationBase[] { },
            // expectedMessage
            new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "dependency_removed" },
        ];

        // candidate pull request matches existing and updating is true => update
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                ExistingPullRequests = [
                    new PullRequest()
                    {
                        Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("1.0.1") }]
                    }
                ],
                UpdatingAPullRequest = true,
            },
            // updatedFiles
            new[]
            {
                new DependencyFile()
                {
                    Directory = "/src/",
                    Name = "project.csproj",
                    Content = "project contents irrelevant",
                }
            },
            // updatedDependencies
            new[]
            {
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    Version = "1.0.1",
                    Requirements = [],
                }
            },
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Dependency",
                    NewVersion = NuGetVersion.Parse("1.0.1"),
                    UpdatedFiles = ["/src/project.csproj"]
                }
            },
            // expectedMessage
            new UpdatePullRequest()
            {
                DependencyGroup = null,
                DependencyNames = ["Some.Dependency"],
                UpdatedDependencyFiles = [new DependencyFile() { Directory = "/src/", Name = "project.csproj", Content = "project contents irrelevant" } ],
                BaseCommitSha = "TEST-COMMIT-SHA",
                CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                PrTitle = RunWorkerTests.TestPullRequestTitle,
                PrBody = RunWorkerTests.TestPullRequestBody,
            }
        ];

        // candidate pull request matches existing group and updating is true => update
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "test/repo",
                },
                ExistingGroupPullRequests = [
                    new GroupPullRequest()
                    {
                        DependencyGroupName = "test-group",
                        Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("1.0.1") }]
                    }
                ],
                UpdatingAPullRequest = true,
            },
            // updatedFiles
            new[]
            {
                new DependencyFile()
                {
                    Directory = "/src/",
                    Name = "project.csproj",
                    Content = "project contents irrelevant",
                }
            },
            // updatedDependencies
            new[]
            {
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    Version = "1.0.1",
                    Requirements = [],
                }
            },
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Dependency",
                    NewVersion = NuGetVersion.Parse("1.0.1"),
                    UpdatedFiles = ["/src/project.csproj"]
                }
            },
            // expectedMessage
            new UpdatePullRequest()
            {
                DependencyGroup = "test-group",
                DependencyNames = ["Some.Dependency"],
                UpdatedDependencyFiles = [new DependencyFile() { Directory = "/src/", Name = "project.csproj", Content = "project contents irrelevant" } ],
                BaseCommitSha = "TEST-COMMIT-SHA",
                CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                PrTitle = RunWorkerTests.TestPullRequestTitle,
                PrBody = RunWorkerTests.TestPullRequestBody,
            }
        ];
    }
}
